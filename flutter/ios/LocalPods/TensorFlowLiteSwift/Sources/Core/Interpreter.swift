// Copyright 2023 The TensorFlow Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

import TensorFlowLiteC

/// Options for configuring a TensorFlow Lite interpreter.
public struct InterpreterOptions {
  /// The number of threads available to the interpreter.
  public var threadCount: Int = 1

  /// Creates default interpreter options.
  public init() {}
}

/// A TensorFlow Lite interpreter that runs inference on a model.
public final class Interpreter {
  /// The C interpreter pointer.
  private var cInterpreter: OpaquePointer?

  /// The interpreter options.
  private let options: InterpreterOptions

  /// The input tensors of the model.
  public private(set) var inputTensors: [Tensor] = []

  /// The output tensors of the model.
  public private(set) var outputTensors: [Tensor] = []

  /// The number of input tensors.
  public var inputTensorCount: Int { return inputTensors.count }

  /// The number of output tensors.
  public var outputTensorCount: Int { return outputTensors.count }

  /// Whether the interpreter has been invoked at least once.
  public private(set) var isInvoked: Bool = false

  /// Creates an interpreter with a model at the given path.
  public init(modelPath: String, options: InterpreterOptions = InterpreterOptions()) throws {
    self.options = options

    guard let cOptions = TfLiteInterpreterOptionsCreate() else {
      throw InterpreterError.failedToCreateInterpreter
    }
    TfLiteInterpreterOptionsSetNumThreads(cOptions, Int32(options.threadCount))

    guard let cModel = TfLiteModelCreateFromFile(modelPath) else {
      TfLiteInterpreterOptionsDelete(cOptions)
      throw InterpreterError.failedToLoadModel
    }

    cInterpreter = TfLiteInterpreterCreate(cModel, cOptions)
    TfLiteModelDelete(cModel)
    TfLiteInterpreterOptionsDelete(cOptions)

    guard cInterpreter != nil else {
      throw InterpreterError.failedToCreateInterpreter
    }
  }

  deinit {
    if let cInterpreter = cInterpreter {
      TfLiteInterpreterDelete(cInterpreter)
    }
  }

  /// Allocates tensors for the interpreter.
  public func allocateTensors() throws {
    guard let cInterpreter = cInterpreter else {
      throw InterpreterError.invalidInterpreter
    }
    let status = TfLiteInterpreterAllocateTensors(cInterpreter)
    guard status == kTfLiteOk else {
      throw InterpreterError.allocateTensorsFailed
    }
    try updateInputTensors()
    try updateOutputTensors()
  }

  /// Invokes the interpreter with the current input tensors.
  public func invoke() throws {
    guard let cInterpreter = cInterpreter else {
      throw InterpreterError.invalidInterpreter
    }
    let status = TfLiteInterpreterInvoke(cInterpreter)
    guard status == kTfLiteOk else {
      throw InterpreterError.invokeFailed
    }
    isInvoked = true
    try updateOutputTensors()
  }

  /// Copies the given data to the input tensor at the given index.
  public func copy(_ data: Data, toInputAt index: Int) throws {
    guard let cInterpreter = cInterpreter,
          index >= 0,
          index < inputTensorCount else {
      throw InterpreterError.invalidTensorIndex
    }

    guard let cTensor = TfLiteInterpreterGetInputTensor(cInterpreter, Int32(index)) else {
      throw InterpreterError.invalidTensor
    }

    let status = data.withUnsafeBytes { (rawBufferPointer: UnsafeRawBufferPointer) in
      TfLiteTensorCopyFromBuffer(cTensor, rawBufferPointer.baseAddress, data.count)
    }
    guard status == kTfLiteOk else {
      throw InterpreterError.copyDataFailed
    }
  }

  /// Returns the data of the output tensor at the given index.
  public func output(at index: Int) throws -> Data {
    guard let cInterpreter = cInterpreter,
          index >= 0,
          index < outputTensorCount else {
      throw InterpreterError.invalidTensorIndex
    }

    guard let cTensor = TfLiteInterpreterGetOutputTensor(cInterpreter, Int32(index)) else {
      throw InterpreterError.invalidTensor
    }

    let byteSize = TfLiteTensorByteSize(cTensor)
    guard let data = TfLiteTensorData(cTensor), byteSize > 0 else {
      throw InterpreterError.invalidTensorData
    }

    return Data(bytes: data, count: byteSize)
  }

  /// Resizes the input tensor at the given index to the given shape.
  public func resizeInput(at index: Int, to shape: [Int]) throws {
    guard let cInterpreter = cInterpreter,
          index >= 0,
          index < inputTensorCount else {
      throw InterpreterError.invalidTensorIndex
    }

    let cDims = shape.map { Int32($0) }
    let status = TfLiteInterpreterResizeInputTensor(
      cInterpreter,
      Int32(index),
      cDims,
      Int32(cDims.count)
    )
    guard status == kTfLiteOk else {
      throw InterpreterError.resizeInputFailed
    }
  }

  /// Applies the given delegate to the interpreter.
  public func add(_ delegate: Delegate) throws {
    guard let cInterpreter = cInterpreter else {
      throw InterpreterError.invalidInterpreter
    }
    guard let cDelegate = delegate.cDelegate else { return }
    let status = TfLiteInterpreterModifyGraphWithDelegate(cInterpreter, cDelegate)
    guard status == kTfLiteOk else {
      throw InterpreterError.delegateApplyFailed
    }
  }

  // MARK: - Private

  private func updateInputTensors() throws {
    guard let cInterpreter = cInterpreter else {
      throw InterpreterError.invalidInterpreter
    }
    let count = TfLiteInterpreterGetInputTensorCount(cInterpreter)
    var tensors: [Tensor] = []
    for i in 0..<Int(count) {
      guard let cTensor = TfLiteInterpreterGetInputTensor(cInterpreter, Int32(i)) else {
        continue
      }
      tensors.append(try tensorFromCTensor(cTensor))
    }
    inputTensors = tensors
  }

  private func updateOutputTensors() throws {
    guard let cInterpreter = cInterpreter else {
      throw InterpreterError.invalidInterpreter
    }
    let count = TfLiteInterpreterGetOutputTensorCount(cInterpreter)
    var tensors: [Tensor] = []
    for i in 0..<Int(count) {
      guard let cTensor = TfLiteInterpreterGetOutputTensor(cInterpreter, Int32(i)) else {
        continue
      }
      tensors.append(try tensorFromCTensor(cTensor))
    }
    outputTensors = tensors
  }

  private func tensorFromCTensor(_ cTensor: UnsafePointer<TfLiteTensor>) throws -> Tensor {
    let name = String(cString: TfLiteTensorName(cTensor))
    let dataType = dataTypeFromCTensor(cTensor)
    let shape = shapeFromCTensor(cTensor)
    let quantizationParams = quantizationFromCTensor(cTensor)
    let byteSize = TfLiteTensorByteSize(cTensor)
    let data: Data
    if let rawData = TfLiteTensorData(cTensor), byteSize > 0 {
      data = Data(bytes: rawData, count: byteSize)
    } else {
      data = Data()
    }
    return Tensor(
      name: name,
      dataType: dataType,
      shape: shape,
      quantizationParameters: quantizationParams,
      data: data
    )
  }

  private func dataTypeFromCTensor(_ cTensor: UnsafePointer<TfLiteTensor>) -> Tensor.DataType {
    switch TfLiteTensorType(cTensor) {
    case kTfLiteBool: return .bool
    case kTfLiteUInt8: return .uInt8
    case kTfLiteInt8: return .int8
    case kTfLiteInt16: return .int16
    case kTfLiteInt32: return .int32
    case kTfLiteInt64: return .int64
    case kTfLiteFloat16: return .float16
    case kTfLiteFloat32: return .float32
    case kTfLiteFloat64: return .float64
    case kTfLiteString: return .string
    default: return .float32
    }
  }

  private func shapeFromCTensor(_ cTensor: UnsafePointer<TfLiteTensor>) -> Tensor.Shape {
    let dims = TfLiteTensorNumDims(cTensor)
    var dimensions: [Int32] = []
    for i in 0..<Int(dims) {
      dimensions.append(Int32(TfLiteTensorDim(cTensor, Int32(i))))
    }
    return Tensor.Shape(dimensions: dimensions)
  }

  private func quantizationFromCTensor(_ cTensor: UnsafePointer<TfLiteTensor>)
    -> Tensor.QuantizationParameters?
  {
    let params = TfLiteTensorQuantizationParams(cTensor)
    if params.scale == 0.0 && params.zero_point == 0 {
      return nil
    }
    return Tensor.QuantizationParameters(
      scale: params.scale,
      zeroPoint: Int(params.zero_point)
    )
  }
}

/// Errors that can occur when using the interpreter.
public enum InterpreterError: Error, Equatable {
  case failedToLoadModel
  case failedToCreateInterpreter
  case invalidInterpreter
  case invalidTensorIndex
  case invalidTensor
  case invalidTensorData
  case allocateTensorsFailed
  case invokeFailed
  case copyDataFailed
  case resizeInputFailed
  case delegateApplyFailed
}

extension InterpreterError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .failedToLoadModel:
      return "Failed to load the TensorFlow Lite model."
    case .failedToCreateInterpreter:
      return "Failed to create the TensorFlow Lite interpreter."
    case .invalidInterpreter:
      return "The interpreter is invalid or has been deallocated."
    case .invalidTensorIndex:
      return "The tensor index is out of range."
    case .invalidTensor:
      return "The tensor is invalid."
    case .invalidTensorData:
      return "The tensor data is invalid."
    case .allocateTensorsFailed:
      return "Failed to allocate tensors."
    case .invokeFailed:
      return "Failed to invoke the interpreter."
    case .copyDataFailed:
      return "Failed to copy data to the input tensor."
    case .resizeInputFailed:
      return "Failed to resize the input tensor."
    case .delegateApplyFailed:
      return "Failed to apply the delegate to the interpreter."
    }
  }
}
