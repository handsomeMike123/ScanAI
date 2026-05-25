// Copyright 2023 The TensorFlow Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

import TensorFlowLiteC
import TensorFlowLiteCCoreML

/// A delegate that uses Core ML for running TensorFlow Lite models.
public class CoreMLDelegate: Delegate {
  /// Options for configuring the Core ML delegate.
  public struct Options {
    /// Which devices should be allowed to use the Core ML delegate.
    public var enabledDevices: EnabledDevices = .all

    /// Creates default Core ML delegate options.
    public init() {}
  }

  /// The devices that can run the Core ML delegate.
  public enum EnabledDevices {
    /// Run only on devices with Apple Neural Engine.
    case devicesWithNeuralEngine
    /// Run on all devices.
    case all
  }

  /// Creates a Core ML delegate with the given options.
  public init(options: Options = Options()) {
    var cOptions = TfLiteCoreMlDelegateOptions()
    switch options.enabledDevices {
    case .all:
      cOptions.enabled_devices = TfLiteCoreMlDelegateAllDevices
    case .devicesWithNeuralEngine:
      cOptions.enabled_devices = TfLiteCoreMlDelegateDevicesWithNeuralEngine
    }
    let cDelegate = TfLiteCoreMlDelegateCreate(&cOptions)
    super.init(cDelegate: cDelegate)
  }
}
