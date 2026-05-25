// Copyright 2023 The TensorFlow Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

import TensorFlowLiteC

/// A TensorFlow Lite delegate that can be applied to a model graph.
open class Delegate {
  /// The C `TfLiteDelegate` pointer.
  public private(set) var cDelegate: UnsafeMutablePointer<TfLiteDelegate>?

  /// Creates a delegate with the given C delegate pointer.
  public init(cDelegate: UnsafeMutablePointer<TfLiteDelegate>?) {
    self.cDelegate = cDelegate
  }

  deinit {
    // TfLiteDelegateDelete is not available in TensorFlowLiteC 2.12.0
    // Delegates are owned by the interpreter and will be freed when it is released
  }
}
