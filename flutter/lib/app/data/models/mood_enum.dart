/// 心情枚举（AffectNet 7 类标签）
enum Mood {
  anger,
  disgust,
  fear,
  happiness,
  neutral,
  sadness,
  surprise;

  /// 中文展示名
  String get displayName {
    switch (this) {
      case Mood.anger:
        return '生气 😤';
      case Mood.disgust:
        return '厌恶 🤢';
      case Mood.fear:
        return '恐惧 😨';
      case Mood.happiness:
        return '开心 😊';
      case Mood.neutral:
        return '中性 😐';
      case Mood.sadness:
        return '悲伤 😔';
      case Mood.surprise:
        return '惊讶 😲';
    }
  }

  /// AffectNet 英文标签
  String get affectNetLabel {
    switch (this) {
      case Mood.anger:
        return 'Anger';
      case Mood.disgust:
        return 'Disgust';
      case Mood.fear:
        return 'Fear';
      case Mood.happiness:
        return 'Happiness';
      case Mood.neutral:
        return 'Neutral';
      case Mood.sadness:
        return 'Sadness';
      case Mood.surprise:
        return 'Surprise';
    }
  }

  /// 对应颜色
  int get colorValue {
    switch (this) {
      case Mood.anger:
        return 0xFFDC143C;
      case Mood.disgust:
        return 0xFF556B2F;
      case Mood.fear:
        return 0xFF483D8B;
      case Mood.happiness:
        return 0xFFFFD700;
      case Mood.neutral:
        return 0xFF808080;
      case Mood.sadness:
        return 0xFF4682B4;
      case Mood.surprise:
        return 0xFFFF8C00;
    }
  }

  /// 描述文案
  String get description {
    switch (this) {
      case Mood.anger:
        return '检测到愤怒情绪，表情紧张';
      case Mood.disgust:
        return '检测到厌恶表情，对某事物反感';
      case Mood.fear:
        return '检测到恐惧情绪，表情不安';
      case Mood.happiness:
        return '检测到积极表情，心情愉悦';
      case Mood.neutral:
        return '表情中性，情绪平稳';
      case Mood.sadness:
        return '检测到悲伤情绪，表情低落';
      case Mood.surprise:
        return '表情惊讶，意想不到';
    }
  }

  /// 从 AffectNet 标签创建
  static Mood fromAffectNetLabel(String label) {
    switch (label) {
      case 'Anger':
        return Mood.anger;
      case 'Disgust':
        return Mood.disgust;
      case 'Fear':
        return Mood.fear;
      case 'Happiness':
        return Mood.happiness;
      case 'Neutral':
        return Mood.neutral;
      case 'Sadness':
        return Mood.sadness;
      case 'Surprise':
        return Mood.surprise;
      default:
        return Mood.neutral;
    }
  }
}

/// 按索引获取 Mood
extension MoodIndex on Mood {
  static Mood fromIndex(int index) => Mood.values[index];
}
