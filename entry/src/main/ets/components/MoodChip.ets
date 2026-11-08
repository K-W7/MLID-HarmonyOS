import { Mood } from '../model/Mood';
import { getMoodColor, getMoodLabel } from '../model/MoodMeta';

@ComponentV2
export struct MoodChip {
  @Require @Param mood: Mood;
  @Param selected: boolean = false;
  @Event onSelect: (mood: Mood) => void = () => {
  };

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 32 → 24：胶囊在暖色底上体量太大，缩小后不再抢视线
      Circle({ width: 24, height: 24 })
        .fill(getMoodColor(this.mood))
    }
    .width(36)
    .height(36)
    .borderRadius(18)
    .border({
      width: this.selected ? 1.5 : 0,
      color: $r('app.color.text_primary')
    })
    .accessibilityText(getMoodLabel(this.mood))
    .onClick(() => {
      this.onSelect(this.mood);
    })
  }
}
