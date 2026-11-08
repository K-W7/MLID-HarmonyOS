/**
 * 加密备份的密码输入面板（导出加密 / 导入解密共用）。
 *
 * 为什么是自绘浮层而不是系统弹窗：系统 AlertDialog 不支持输入框；
 * 自绘面板还能挂官方材质，与设置页的浮层风格一致。
 */
@ComponentV2
export struct BackupPasswordPanel {
  /** 面板标题，例如「加密导出」「输入备份密码」 */
  @Param title: string = '加密备份';
  /** 副标题/说明 */
  @Param hint: string = '密码至少 8 位，忘记就无法恢复。';
  /** false 时不渲染 */
  @Param visible: boolean = false;

  @Event onCancel: () => void = () => {
  };
  @Event onConfirm: (password: string) => void = () => {
  };

  @Local password: string = '';
  @Local errorText: string = '';

  build() {
    if (this.visible) {
      Stack({ alignContent: Alignment.Center }) {
        // 遮罩：点空白取消
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.overlay_scrim'))
          .onClick(() => {
            this.reset();
            this.onCancel();
          })

        Column({ space: 12 }) {
          Text(this.title)
            .width('100%')
            .fontSize($r('app.float.font_body'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))

          Text(this.hint)
            .width('100%')
            .fontSize($r('app.float.font_meta_small'))
            .fontColor($r('app.color.text_secondary'))

          TextInput({ placeholder: '输入密码', text: this.password })
            .type(InputType.Password)
            .width('100%')
            .height(44)
            .fontSize($r('app.float.font_body_small'))
            .backgroundColor($r('app.color.bg_page'))
            .borderRadius($r('app.float.radius_button'))
            .onChange((value: string) => {
              this.password = value;
              this.errorText = '';
            })

          if (this.errorText !== '') {
            Text(this.errorText)
              .width('100%')
              .fontSize($r('app.float.font_meta_small'))
              .fontColor($r('app.color.danger_low_sat'))
          }

          Row({ space: 12 }) {
            Text('取消')
              .layoutWeight(1)
              .height(42)
              .textAlign(TextAlign.Center)
              .fontSize($r('app.float.font_body_small'))
              .fontColor($r('app.color.text_primary'))
              .backgroundColor($r('app.color.button_secondary_bg'))
              .borderRadius($r('app.float.radius_button'))
              .onClick(() => {
                this.reset();
                this.onCancel();
              })

            Text('确定')
              .layoutWeight(1)
              .height(42)
              .textAlign(TextAlign.Center)
              .fontSize($r('app.float.font_body_small'))
              .fontColor($r('app.color.white'))
              .backgroundColor($r('app.color.brand_primary'))
              .borderRadius($r('app.float.radius_button'))
              .onClick(() => {
                if (this.password.length < 8) {
                  this.errorText = '密码至少 8 位';
                  return;
                }
                const value = this.password;
                this.reset();
                this.onConfirm(value);
              })
          }
          .width('100%')
          .margin({ top: 4 })
        }
        .width('86%')
        .padding(20)
        .backgroundColor($r('app.color.bg_card'))
        .borderRadius($r('app.float.radius_card'))
        .border({ width: 1, color: $r('app.color.shadow_card') })
        .shadow({ radius: 16, color: $r('app.color.shadow_card'), offsetY: 6 })
      }
      .width('100%')
      .height('100%')
      .zIndex(100)
    }
  }

  private reset(): void {
    this.password = '';
    this.errorText = '';
  }
}
