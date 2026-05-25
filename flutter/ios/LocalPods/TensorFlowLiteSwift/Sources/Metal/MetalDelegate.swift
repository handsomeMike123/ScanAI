// Copyright 2023 The TensorFlow Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

import TensorFlowLiteC
import TensorFlowLiteCMetal

/// A delegate that uses the Metal GPU for running TensorFlow Lite models.
public class MetalDelegate: Delegate {
  /// Options for configuring the Metal delegate.
  public struct Options {
    /// Whether to allow the Metal delegate to fall back to CPU.
    public var isQuantizationModelAllowed: Bool = false

    /// Whether to enable precision loss allowed.
    public var allowPrecisionLoss: Bool = false

    /// Whether to wait until the delegate is ready.
    public var waitType: WaitType = .passive

    /// Creates default Metal delegate options.
    public init() {}
  }

  /// The wait type for the Metal delegate.
  public enum WaitType {
    /// Passive wait.
    case passive
    /// Active wait.
    case active
    /// Aggressive wait.
    case aggressive
  }

  /// Creates a Metal delegate with the given options.
  public init(options: Options = Options()) {
    var cOptions = TFLGpuDelegateOptions(
      allow_precision_loss: options.allowPrecisionLoss,
      wait_type: {
        switch options.waitType {
        case .passive: return TFLGpuDelegateWaitTypePassive
        case .active: return TFLGpuDelegateWaitTypeActive
        case .aggressive: return TFLGpuDelegateWaitTypeAggressive
        }
      }(),
      enable_quantization: options.isQuantizationModelAllowed
    )
    let cDelegate = TFLGpuDelegateCreate(&cOptions)
    super.init(cDelegate: cDelegate)
  }
}
