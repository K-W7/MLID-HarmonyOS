/**
 * 加密备份容器 `.mlidbackup`（formatVersion = 1）的加解密。
 *
 * 规格来源：MLID-SRS-SDD-001 8.4.2。容器 = 50 字节明文头 + AES-256-GCM 密文（末尾 16 字节为认证标签）。
 * 明文头整段作为 AAD，所以头里任何一个字节被改都会让 GCM 认证失败，不需要另加签名。
 *
 * 与 ImportExport.ets 的关系：本模块只吃 / 吐 ZIP 字节，不读写文件、不碰 ZIP 内容结构。
 * 上层把 zlib.compressFile 产出的字节直接传进来；解密拿到的字节再交给 zlib.decompressFile。
 *
 * 为什么不缓存密码和派生密钥：导出的密码只在这一条调用栈里活着，用完即丢；
 * 派生密钥数组在交给 SymKey 后立刻 fill(0)，SymKey 在 finally 里 clearMem()。这样即使进程内存被 dump，
 * 里面也不会长期留着一份密钥材料。
 */
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { BusinessError } from '@kit.BasicServicesKit';

/** 头部固定长度（规格 8.4.2）：密文紧跟在第 50 字节之后。 */
export const HEADER_LENGTH: number = 50;

/** 错误分类：调用方靠它区分「不是加密备份」「密码错」「文件损坏」，而不是靠猜错误文案。 */
export enum BackupCryptoErrorCode {
  /** 文件太短或 magic 不是 MLID —— 很可能是普通 ZIP，应回退到普通导入流程。 */
  NOT_BACKUP = 'NOT_BACKUP',
  /** formatVersion 不受支持（高于当前实现）。 */
  UNSUPPORTED_VERSION = 'UNSUPPORTED_VERSION',
  /** kdfId 不受支持。 */
  UNSUPPORTED_KDF = 'UNSUPPORTED_KDF',
  /** 头内部字段自相矛盾（saltLen / nonceLen / iterations / 长度溢出）。 */
  HEADER_CORRUPT = 'HEADER_CORRUPT',
  /** 头声明的 ciphertextLength 与文件实际长度不一致 —— 文件被截断或被追加过。 */
  LENGTH_MISMATCH = 'LENGTH_MISMATCH',
  /** 密码不足 8 字符。 */
  WEAK_PASSWORD = 'WEAK_PASSWORD',
  /** 加解密调用本身失败（算法名不支持、密钥长度不符等）。 */
  CRYPTO_FAILED = 'CRYPTO_FAILED',
  /** GCM 认证失败：密码错、头被改、密文被改、标签被改，四者不可区分。 */
  AUTH_FAILED = 'AUTH_FAILED'
}

/** 只读头解析结果。salt / nonce 是拷贝，调用方改它们不会影响原文件字节。 */
export interface BackupHeaderInfo {
  formatVersion: number;
  kdfId: number;
  iterations: number;
  salt: Uint8Array;
  nonce: Uint8Array;
  ciphertextLength: number;
}

// ---- 规格常量，全部来自 8.4.2，改动即意味着要提升 formatVersion ----

/** magic "MLID"，4 字节 ASCII。 */
const MAGIC: Uint8Array = new Uint8Array([0x4D, 0x4C, 0x49, 0x44]);
const FORMAT_VERSION: number = 1;
/** kdfId = 1：PBKDF2-HMAC-SHA256。 */
const KDF_ID_PBKDF2_SHA256: number = 1;
/** 已发布的迭代次数，冻结。解密时必须读头里的值，不能假定等于这个常量。 */
const PBKDF2_ITERATIONS: number = 210000;
const SALT_LENGTH: number = 16;
const NONCE_LENGTH: number = 12;
/** GCM 认证标签长度，框架固定 16 字节。 */
const TAG_LENGTH: number = 16;
/** AES-256 密钥 32 字节。 */
const KEY_LENGTH: number = 32;
const MIN_PASSWORD_LENGTH: number = 8;
/** 头里的 iterations 上限。头虽被认证，但派生发生在认证之前，不能让伪造的头把线程拖死。 */
const MAX_ITERATIONS: number = 10000000;

// ---- 算法名字符串。全部照 @ohos.security.cryptoFramework.d.ts 的注释写 ----
// createKdf 要「算法|摘要」（d.ts:6257-6259 的例子 PBKDF2|SHA256）；
// PBKDF2Spec.algName 只要算法族名（KdfSpec 注释 d.ts:5908 的例子就是 PBKDF2）。
const KDF_ALG_NAME: string = 'PBKDF2|SHA256';
const KDF_FAMILY: string = 'PBKDF2';
const SYM_KEY_ALG_NAME: string = 'AES256';
/**
 * AES-256-GCM，NoPadding。
 * GCM 是流式的，密文与明文等长；用 NoPadding 才能让 ciphertextLength 在加密前就确定
 * （= 明文长度 + 16），而它又必须写进被认证的头里。若改成 PKCS7，明文会被填充到 16 的倍数，
 * 长度公式与已固化的测试向量都会变，属于格式变更。
 */
const CIPHER_TRANSFORMATION: string = 'AES256|GCM|NoPadding';
/** GcmParamsSpec.algName 要写子类名，让 init() 知道该按哪个子类解释参数（d.ts:166-167）。 */
const GCM_PARAMS_ALG_NAME: string = 'GcmParamsSpec';

function backupError(code: BackupCryptoErrorCode, detail: string): Error {
  return new Error(`[${code}] ${detail}`);
}

/**
 * 从捕获到的异常里取回本模块的错误码；不是本模块抛的就返回空串，调用方据此决定是否转述给用户。
 * 用消息前缀而不是自定义 Error 子类，是为了在 ArkTS 严格模式下保持行为确定（字符串是唯一稳定可比的）。
 */
export function cryptoErrorCodeOf(err: Error): string {
  if (err === null || err === undefined) {
    return '';
  }
  const message: string = err.message;
  if (message === undefined || message.length < 3 || message.charAt(0) !== '[') {
    return '';
  }
  const end: number = message.indexOf(']');
  if (end <= 1) {
    return '';
  }
  return message.substring(1, end);
}

// ---- 大端读写。所有整数按规格为大端；8 字节字段用 number 分段写，避免 BigInt ----

function writeUint32BE(out: Uint8Array, offset: number, value: number): void {
  out[offset] = (value >>> 24) & 0xFF;
  out[offset + 1] = (value >>> 16) & 0xFF;
  out[offset + 2] = (value >>> 8) & 0xFF;
  out[offset + 3] = value & 0xFF;
}

/** 用乘法而不是 <<，否则 0x80 开头的字节会让结果变成负数。 */
function readUint32BE(src: Uint8Array, offset: number): number {
  return src[offset] * 0x1000000 + src[offset + 1] * 0x10000 + src[offset + 2] * 0x100 + src[offset + 3];
}

const MAX_SAFE_INTEGER_VALUE: number = 9007199254740991;

function writeUint64BE(out: Uint8Array, offset: number, value: number): void {
  if (value < 0 || value > MAX_SAFE_INTEGER_VALUE) {
    throw backupError(BackupCryptoErrorCode.HEADER_CORRUPT, `长度 ${value} 超出可写范围`);
  }
  const high: number = Math.floor(value / 0x100000000);
  const low: number = value - high * 0x100000000;
  writeUint32BE(out, offset, high);
  writeUint32BE(out, offset + 4, low);
}

function readUint64BE(src: Uint8Array, offset: number): number {
  const high: number = readUint32BE(src, offset);
  const low: number = readUint32BE(src, offset + 4);
  // 超过 2^53-1 的整数在 JS 里已无法精确表示；备份文件不可能这么大，直接判为头损坏。
  if (high > 0x1FFFFF) {
    throw backupError(BackupCryptoErrorCode.HEADER_CORRUPT, 'ciphertextLength 超出可表示范围');
  }
  return high * 0x100000000 + low;
}

// ---- 头 ----

/**
 * 按 8.4.2 的偏移表拼出 50 字节明文头。
 * 这片数组既是文件开头，也是 AAD：加密和校验必须用同一份字节，所以这里只生成一次。
 */
function buildHeader(salt: Uint8Array, nonce: Uint8Array, ciphertextLength: number): Uint8Array {
  const header: Uint8Array = new Uint8Array(HEADER_LENGTH); // 新数组全 0，保留位 6~7 因此天然为 0
  header.set(MAGIC, 0); // 0..3
  header[4] = FORMAT_VERSION; // 4
  header[5] = KDF_ID_PBKDF2_SHA256; // 5
  // 6..7 保留，规格要求填 0
  writeUint32BE(header, 8, PBKDF2_ITERATIONS); // 8..11
  header[12] = SALT_LENGTH; // 12
  header.set(salt, 13); // 13..28
  header[29] = NONCE_LENGTH; // 29
  header.set(nonce, 30); // 30..41
  writeUint64BE(header, 42, ciphertextLength); // 42..49
  return header;
}

/**
 * 只读头，不解密、不派生密钥，给上层做「是不是加密备份 / 版本是多少」的预判。
 * 除了格式字段，也顺手校验 ciphertextLength 与文件实际长度是否吻合：截断的文件在这里就该被拒，
 * 而不是等解密到一半才报错。
 */
export function readHeader(fileBytes: Uint8Array): BackupHeaderInfo {
  if (fileBytes === null || fileBytes === undefined || fileBytes.length < HEADER_LENGTH) {
    throw backupError(BackupCryptoErrorCode.NOT_BACKUP, `文件不足 ${HEADER_LENGTH} 字节，不是加密备份`);
  }
  for (let i = 0; i < MAGIC.length; i++) {
    if (fileBytes[i] !== MAGIC[i]) {
      throw backupError(BackupCryptoErrorCode.NOT_BACKUP, 'magic 不是 "MLID"，不是 .mlidbackup 容器');
    }
  }
  const formatVersion: number = fileBytes[4];
  if (formatVersion !== FORMAT_VERSION) {
    throw backupError(BackupCryptoErrorCode.UNSUPPORTED_VERSION,
      `formatVersion=${formatVersion}，当前实现只认 ${FORMAT_VERSION}，请升级应用`);
  }
  const kdfId: number = fileBytes[5];
  if (kdfId !== KDF_ID_PBKDF2_SHA256) {
    throw backupError(BackupCryptoErrorCode.UNSUPPORTED_KDF, `kdfId=${kdfId}，当前实现只认 PBKDF2-HMAC-SHA256`);
  }
  // 6..7 保留位不校验取值：v1 布局固定，且它们被 AAD 覆盖，被改会在认证阶段失败。
  const iterations: number = readUint32BE(fileBytes, 8);
  if (iterations <= 0 || iterations > MAX_ITERATIONS) {
    throw backupError(BackupCryptoErrorCode.HEADER_CORRUPT, `iterations=${iterations} 不合理`);
  }
  const saltLen: number = fileBytes[12];
  if (saltLen !== SALT_LENGTH) {
    // 长度字段与 v1 的固定偏移冲突时无法继续解析后面的字段，只能判为损坏。
    throw backupError(BackupCryptoErrorCode.HEADER_CORRUPT, `saltLen=${saltLen}，v1 固定为 ${SALT_LENGTH}`);
  }
  const salt: Uint8Array = fileBytes.slice(13, 13 + SALT_LENGTH);
  const nonceLen: number = fileBytes[29];
  if (nonceLen !== NONCE_LENGTH) {
    throw backupError(BackupCryptoErrorCode.HEADER_CORRUPT, `nonceLen=${nonceLen}，v1 固定为 ${NONCE_LENGTH}`);
  }
  const nonce: Uint8Array = fileBytes.slice(30, 30 + NONCE_LENGTH);
  const ciphertextLength: number = readUint64BE(fileBytes, 42);
  if (ciphertextLength < TAG_LENGTH) {
    throw backupError(BackupCryptoErrorCode.HEADER_CORRUPT, `ciphertextLength=${ciphertextLength} 装不下 ${TAG_LENGTH} 字节认证标签`);
  }
  const expectedLength: number = HEADER_LENGTH + ciphertextLength;
  if (fileBytes.length !== expectedLength) {
    throw backupError(BackupCryptoErrorCode.LENGTH_MISMATCH,
      `头声明总长 ${expectedLength} 字节（50 + ${ciphertextLength}），实际 ${fileBytes.length} 字节`);
  }
  const info: BackupHeaderInfo = {
    formatVersion: formatVersion,
    kdfId: kdfId,
    iterations: iterations,
    salt: salt,
    nonce: nonce,
    ciphertextLength: ciphertextLength
  };
  return info;
}

// ---- Uint8Array <-> DataBlob 转换 ----

/** DataBlob 就是「一个 data 字段装着 Uint8Array」的壳（d.ts:132-144），这里集中转换，避免各处手写壳子。 */
function toBlob(bytes: Uint8Array): cryptoFramework.DataBlob {
  const blob: cryptoFramework.DataBlob = { data: bytes };
  return blob;
}

/**
 * GcmParamsSpec 的三个 DataBlob：
 * - iv：12 字节 nonce；
 * - aad：50 字节明文头，加密解密都必须是同一份字节，否则认证必败；
 * - authTag：解密时是密文末尾的 16 字节标签；加密时框架自己产生标签，占位即可（见 encryptBackup）。
 */
function buildGcmParams(nonce: Uint8Array, header: Uint8Array, tag: Uint8Array): cryptoFramework.GcmParamsSpec {
  const params: cryptoFramework.GcmParamsSpec = {
    algName: GCM_PARAMS_ALG_NAME,
    iv: toBlob(nonce),
    aad: toBlob(header),
    authTag: toBlob(tag)
  };
  return params;
}

// ---- 密钥 ----

function assertPassword(password: string): void {
  // 按 UTF-16 码元计数，与输入框限制一致；不 trim，避免悄悄改掉用户密码里的空格。
  if (password === null || password === undefined || password.length < MIN_PASSWORD_LENGTH) {
    throw backupError(BackupCryptoErrorCode.WEAK_PASSWORD, `密码至少 ${MIN_PASSWORD_LENGTH} 个字符`);
  }
}

/**
 * 用给定 keySize 跑一次 PBKDF2，只负责拿字节，不判断对错。
 */
async function deriveWithKeySize(password: string, salt: Uint8Array, iterations: number, keySize: number): Promise<Uint8Array> {
  const spec: cryptoFramework.PBKDF2Spec = {
    algName: KDF_FAMILY,
    password: password,
    salt: salt,
    iterations: iterations,
    keySize: keySize
  };
  // createKdf 每次新建：Kdf 实例无状态，但按规格不跨调用复用任何密码相关对象。
  // 框架抛的 BusinessError 直接向上冒泡，deriveKey 靠原始错误码判断是「keySize 语义不对」还是「真的派生失败」；
  // ArkTS 禁止 throw 任意类型，所以这里不能再包一层 try/catch 原样重抛。
  const kdf: cryptoFramework.Kdf = cryptoFramework.createKdf(KDF_ALG_NAME);
  const secret: cryptoFramework.DataBlob = await kdf.generateSecret(spec);
  return secret.data;
}

/**
 * PBKDF2-HMAC-SHA256 派生 32 字节 AES-256 密钥。
 *
 * 先按 d.ts 的说明把 keySize 当「字节」传 32（d.ts:5966）。个别版本若把 keySize 当比特，
 * 第一轮只会返回 4 字节，此时按比特传 256 再跑一次；两条路径产出的 32 字节密钥完全相同，
 * 所以这个兜底不会影响已固化的测试向量。最终长度必须正好 32，否则宁可报错也不拿半截密钥去加密。
 */
async function deriveKey(password: string, salt: Uint8Array, iterations: number): Promise<Uint8Array> {
  const candidates: number[] = [KEY_LENGTH, KEY_LENGTH * 8];
  let lastDetail: string = '';
  for (let i = 0; i < candidates.length; i++) {
    try {
      const derived: Uint8Array = await deriveWithKeySize(password, salt, iterations, candidates[i]);
      if (derived.length === KEY_LENGTH) {
        return derived;
      }
      lastDetail = `keySize=${candidates[i]} 返回 ${derived.length} 字节`;
    } catch (e) {
      const biz = e as BusinessError;
      lastDetail = `keySize=${candidates[i]} 抛错 ${biz.code}`;
    }
  }
  throw backupError(BackupCryptoErrorCode.CRYPTO_FAILED, `PBKDF2 派生失败（${lastDetail}）`);
}

/** 把 32 字节原始密钥交给 AES256 的密钥生成器，转换出的 SymKey 才能用于 AES-GCM。 */
async function createAesKey(keyBytes: Uint8Array): Promise<cryptoFramework.SymKey> {
  try {
    const generator: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator(SYM_KEY_ALG_NAME);
    // convertKey 会校验密钥长度必须等于 256 位，长度不对会在这里报错，不会产出一个弱密钥对象。
    const symKey: cryptoFramework.SymKey = await generator.convertKey(toBlob(keyBytes));
    return symKey;
  } catch (e) {
    const biz = e as BusinessError;
    throw backupError(BackupCryptoErrorCode.CRYPTO_FAILED, `AES-256 密钥转换失败（框架错误码 ${biz.code}）`);
  }
}

/** 每类失败给出不同的原因：认证失败时密码错和文件被改在密码学上无法区分，文案要如实说。 */
function describeDecryptFailure(e: BusinessError): string {
  return `GCM 认证失败：密码错误，或文件头 / 密文 / 认证标签被改动（框架错误码 ${e.code}）`;
}

// ---- 对外接口 ----

/**
 * 普通 ZIP 字节 -> `.mlidbackup` 文件字节。
 * 头的 salt / nonce 每次重新随机；iterations 用规格常量；AAD 就是刚生成的那 50 字节头。
 */
export async function encryptBackup(zipBytes: Uint8Array, password: string): Promise<Uint8Array> {
  assertPassword(password);
  if (zipBytes === null || zipBytes === undefined || zipBytes.length === 0) {
    throw backupError(BackupCryptoErrorCode.CRYPTO_FAILED, '待加密的 ZIP 字节为空，先确认上层压缩成功');
  }

  let salt: Uint8Array = new Uint8Array(0);
  let nonce: Uint8Array = new Uint8Array(0);
  try {
    // 每次导出都重新取随机 salt / nonce，绝不复用（规格 8.4.2 第 4 条）。
    const random: cryptoFramework.Random = cryptoFramework.createRandom();
    salt = (await random.generateRandom(SALT_LENGTH)).data;
    nonce = (await random.generateRandom(NONCE_LENGTH)).data;
  } catch (e) {
    const biz = e as BusinessError;
    throw backupError(BackupCryptoErrorCode.CRYPTO_FAILED, `salt/nonce 随机数生成失败（框架错误码 ${biz.code}）`);
  }
  if (salt.length !== SALT_LENGTH || nonce.length !== NONCE_LENGTH) {
    // 随机源返回的长度不对就没法写头，直接失败比写出一个畸形文件好。
    throw backupError(BackupCryptoErrorCode.CRYPTO_FAILED, '随机数长度不符，salt/nonce 生成失败');
  }

  // NoPadding 下密文主体与明文等长，再追加 16 字节标签，所以长度在加密前就能定。
  const ciphertextLength: number = zipBytes.length + TAG_LENGTH;
  const header: Uint8Array = buildHeader(salt, nonce, ciphertextLength);

  const keyBytes: Uint8Array = await deriveKey(password, salt, PBKDF2_ITERATIONS);
  const symKey: cryptoFramework.SymKey = await createAesKey(keyBytes);
  keyBytes.fill(0); // SymKey 已持有密钥副本，原始字节留着没有意义

  try {
    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher(CIPHER_TRANSFORMATION);
    // 加密阶段标签由 doFinal 产出，这里的占位标签不会被使用；长度取 16 只是为了满足接口对 authTag 的要求。
    const placeholderTag: Uint8Array = new Uint8Array(TAG_LENGTH);
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, buildGcmParams(nonce, header, placeholderTag));
    // GCM 单次 doFinal 即可：返回值的末尾 16 字节就是认证标签（d.ts:273-281），不需要再单独取。
    const sealed: cryptoFramework.DataBlob = await cipher.doFinal(toBlob(zipBytes));
    if (sealed.data.length !== ciphertextLength) {
      throw backupError(BackupCryptoErrorCode.CRYPTO_FAILED,
        `加密输出 ${sealed.data.length} 字节，与头声明并参与认证的 ${ciphertextLength} 字节不符`);
    }
    const fileBytes: Uint8Array = new Uint8Array(HEADER_LENGTH + sealed.data.length);
    fileBytes.set(header, 0);
    fileBytes.set(sealed.data, HEADER_LENGTH);
    return fileBytes;
  } catch (e) {
    const failure = e as Error;
    if (cryptoErrorCodeOf(failure) !== '') {
      throw failure; // 本模块自己的错误原样上抛，保留错误码
    }
    const biz = e as BusinessError;
    throw backupError(BackupCryptoErrorCode.CRYPTO_FAILED, `AES-GCM 加密失败（框架错误码 ${biz.code}）`);
  } finally {
    try {
      symKey.clearMem();
    } catch (clearError) {
      // 清理失败不影响已经完成的加密结果，也不能把成功改判成失败
    }
  }
}

/**
 * `.mlidbackup` 文件字节 -> 普通 ZIP 字节。
 * 先校验头（magic / 版本 / kdf / 长度）再解密；认证不通过就抛错，绝不返回半截明文。
 */
export async function decryptBackup(fileBytes: Uint8Array, password: string): Promise<Uint8Array> {
  assertPassword(password);
  // readHeader 已保证 magic / 版本 / kdf / ciphertextLength 与文件实际长度全部自洽
  const header: BackupHeaderInfo = readHeader(fileBytes);

  // 密文区 = 文件第 50 字节之后；末尾 16 字节是标签，主体不含标签。
  const ciphertext: Uint8Array = fileBytes.slice(HEADER_LENGTH);
  const bodyLength: number = ciphertext.length - TAG_LENGTH;
  if (bodyLength < 0) {
    throw backupError(BackupCryptoErrorCode.HEADER_CORRUPT, '密文区不足 16 字节，连认证标签都装不下');
  }
  const body: Uint8Array = ciphertext.slice(0, bodyLength);
  const tag: Uint8Array = ciphertext.slice(bodyLength);
  // AAD 必须与文件里那 50 字节逐字节相同，这里从原文件再切一份，不依赖上面解析时的任何重编码。
  const headerBytes: Uint8Array = fileBytes.slice(0, HEADER_LENGTH);

  // iterations 用头里的值：它参与认证，改了就派生不出正确的密钥。
  const keyBytes: Uint8Array = await deriveKey(password, header.salt, header.iterations);
  const symKey: cryptoFramework.SymKey = await createAesKey(keyBytes);
  keyBytes.fill(0);

  try {
    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher(CIPHER_TRANSFORMATION);
    await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, buildGcmParams(header.nonce, headerBytes, tag));
    const opened: cryptoFramework.DataBlob = await cipher.doFinal(toBlob(body));
    if (opened.data.length !== bodyLength) {
      throw backupError(BackupCryptoErrorCode.AUTH_FAILED,
        `解密输出 ${opened.data.length} 字节，与密文主体 ${bodyLength} 字节不符（NoPadding 下应完全相等）`);
    }
    return opened.data;
  } catch (e) {
    const failure = e as Error;
    if (cryptoErrorCodeOf(failure) !== '') {
      throw failure;
    }
    // 密码错、头被改、密文被改都表现为这里的引擎错误，语义上不可区分，统一报认证失败。
    throw backupError(BackupCryptoErrorCode.AUTH_FAILED, describeDecryptFailure(e as BusinessError));
  } finally {
    try {
      symKey.clearMem();
    } catch (clearError) {
      // 同上：清理失败不改变本次解密的结论
    }
  }
}
