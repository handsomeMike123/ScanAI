/// 应用常量
class AppConstants {
  AppConstants._();

  /// 应用名称
  static const String appName = 'AI 扫描';

  /// 模型输入尺寸
  static const int modelInputSize = 224;

  /// 模型文件名（EmotiEff enet_b2_7，AffectNet 7分类情绪识别模型）
  static const String modelFileName = 'EmotiEff_enet_b2_7_fp32.tflite';

  /// 模型输入通道数 (RGB)
  static const int modelChannels = 3;

  /// AffectNet 7类标签
  /// 标签顺序必须与模型输出节点一致，否则推理结果会错位
  static const List<String> affectNetLabels = [
    'Anger',
    'Disgust',
    'Fear',
    'Happiness',
    'Neutral',
    'Sadness',
    'Surprise',
  ];

  /// AffectNet 中文标签（与上面英文一一对应）
  static const List<String> affectNetLabelsCN = [
    '生气 😤',
    '厌恶 🤢',
    '恐惧 😨',
    '开心 😊',
    '中性 😐',
    '悲伤 😔',
    '惊讶 😲',
  ];

  /// 心情描述
  static const List<String> affectNetDescriptions = [
    '检测到愤怒情绪，表情紧张',
    '检测到厌恶表情，对某事物反感',
    '检测到恐惧情绪，表情不安',
    '检测到积极表情，心情愉悦',
    '表情中性，情绪平稳',
    '检测到悲伤情绪，表情低落',
    '表情惊讶，意想不到',
  ];

  /// 心情对应颜色 (ARGB)
  static const List<int> affectNetColors = [
    0xFFDC143C, // 深红 - Anger
    0xFF556B2F, // 暗橄榄绿 - Disgust
    0xFF483D8B, // 暗蓝 - Fear
    0xFFFFD700, // 金色 - Happiness
    0xFF808080, // 灰色 - Neutral
    0xFF4682B4, // 钢蓝 - Sadness
    0xFFFF8C00, // 深橙 - Surprise
  ];

  /// 实时检测间隔（秒）
  static const int detectionIntervalSeconds = 3;

  /// 人脸裁剪边距比例
  static const double faceCropMarginRatio = 0.4;

  /// 相机图像宽度
  static const int cameraImageWidth = 640;

  /// 相机图像高度
  static const int cameraImageHeight = 480;
}
