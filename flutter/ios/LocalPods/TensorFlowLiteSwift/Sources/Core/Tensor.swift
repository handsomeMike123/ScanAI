// Copyright 2023 The TensorFlow Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

import TensorFlowLiteC

/// A tensor in the TensorFlow Lite runtime.
public struct Tensor {
  /// The name of the tensor.
  public let name: String

  /// The data type of the tensor.
  public let dataType: DataType

  /// The shape of the tensor.
  public let shape: Shape

  /// The quantization parameters for the tensor.
  public let quantizationParameters: QuantizationParameters?

  /// The data of the tensor.
  public var data: Data

  /// Creates a tensor with the given properties.
  public init(
    name: String,
    dataType: DataType,
    shape: Shape,
    quantizationParameters: QuantizationParameters? = nil,
    data: Data
  ) {
    self.name = name
    self.dataType = dataType
    self.shape = shape
    self.quantizationParameters = quantizationParameters
    self.data = data
  }

  /// Data type for a tensor.
  public enum DataType: Equatable {
    case bool
    case uInt8
    case int8
    case int16
    case int32
    case int64
    case float16
    case float32
    case float64
    case string

    /// The size in bytes of a single element of this data type.
    public var byteSize: Int {
      switch self {
      case .bool: return 1
      case .uInt8: return 1
      case .int8: return 1
      case .int16: return 2
      case .int32: return 4
      case .int64: return 8
      case .float16: return 2
      case .float32: return 4
      case .float64: return 8
      case .string: return -1
      }
    }
  }

  /// Shape of a tensor.
  public struct Shape: Equatable {
    /// The array of dimensions.
    public let dimensions: [Int]

    /// The number of elements in the tensor.
    public var count: Int {
      if dimensions.isEmpty { return 0 }
      return dimensions.reduce(1, *)
    }

    /// Creates a shape with the given dimensions.
    public init(dimensions: [Int]) {
      self.dimensions = dimensions
    }

    /// Creates a shape with the given array of `Int32` dimensions.
    public init(dimensions: [Int32]) {
      self.dimensions = dimensions.map { Int($0) }
    }
  }

  /// Quantization parameters for a quantized tensor.
  public struct QuantizationParameters: Equatable {
    /// The scale factor used in quantization.
    public let scale: Float

    /// The zero point used in quantization.
    public let zeroPoint: Int

    /// Creates quantization parameters.
    public init(scale: Float, zeroPoint: Int) {
      self.scale = scale
      self.zeroPoint = zeroPoint
    }
  }
}
