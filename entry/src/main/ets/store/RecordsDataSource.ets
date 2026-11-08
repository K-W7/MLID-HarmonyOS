import { RecordItem } from '../model/RecordItem';

class RecordsDataSource implements IDataSource {
  private items: RecordItem[] = [];
  private listeners: DataChangeListener[] = [];

  constructor(items: RecordItem[]) {
    this.items = items;
  }

  updateItems(items: RecordItem[]): void {
    this.items = items;
    this.notifyReload();
  }

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): RecordItem {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    const idx = this.listeners.indexOf(listener);
    if (idx < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const idx = this.listeners.indexOf(listener);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  private notifyReload(): void {
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }
}

export default RecordsDataSource;
