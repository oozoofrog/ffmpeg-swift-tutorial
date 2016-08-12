//
//  Castable.swift
//  Castable
//
//  Created by jayios on 2016. 6. 23..
//  Copyright © 2016년 ngenii. All rights reserved.
//

import Foundation
import CoreGraphics
import SDL
import AVFoundation

protocol Castable {}

protocol UnsafePointerProtocol {
    associatedtype Pointee
    
    init<Memory>(_ from: UnsafeMutablePointer<Memory>)
    init<Memory>(_ from: UnsafePointer<Memory>)
    var pointee: Pointee { get }
}

extension UnsafeMutablePointer : UnsafePointerProtocol, Castable{}
extension UnsafePointer : UnsafePointerProtocol, Castable{}

extension UnsafePointerProtocol where Self: Castable {
    func cast<P: UnsafePointerProtocol, M where M == P.Pointee>() -> P? {
        switch self {
        case let ptr as UnsafePointer<Pointee>:
            return P(ptr)
        case let ptr as UnsafeMutablePointer<Pointee>:
            return P(ptr)
        default:
            return nil
        }
    }
    
    func mutable<M>() -> UnsafeMutablePointer<M>? {
        switch self {
        case let ptr as UnsafePointer<Pointee>:
            return UnsafeMutablePointer<M>(ptr)
        case let ptr as UnsafeMutablePointer<Pointee>:
            return UnsafeMutablePointer<M>(ptr)
        default:
            return nil
        }
    }
}


protocol Pointerable {
    associatedtype Element
    var pointer: UnsafePointer<Element>? {get}
}

extension Array : Pointerable {}
extension ArraySlice : Pointerable {
    func array() -> Array<Element> {
        return Array<Element>(self)
    }
}

extension Pointerable where Self: Sequence {
    var pointer: UnsafePointer<Element>? {
        switch self {
        case let a as Array<Element>:
            return UnsafePointer<Element>(a)
        case let s as ArraySlice<Element>:
            return UnsafePointer<Element>(s.array())
        default:
            return nil
        }
    }
}

protocol ArithmeticCastable: Comparable, Equatable, Hashable {
    init(_ value: Int)
    init(_ value: Int8)
    init(_ value: Int16)
    init(_ value: Int32)
    init(_ value: Int64)
    init(_ value: UInt)
    init(_ value: UInt8)
    init(_ value: UInt16)
    init(_ value: UInt32)
    init(_ value: UInt64)
    init(_ value: Float)
    init(_ value: Double)
    init(_ value: CGFloat)
}

extension Int: ArithmeticCastable{}
extension Int8: ArithmeticCastable{}
extension Int16: ArithmeticCastable{}
extension Int32: ArithmeticCastable{}
extension Int64: ArithmeticCastable{}
extension UInt: ArithmeticCastable{}
extension UInt8: ArithmeticCastable{}
extension UInt16: ArithmeticCastable{}
extension UInt32: ArithmeticCastable{}
extension UInt64: ArithmeticCastable{}
extension Float: ArithmeticCastable{}
extension Double: ArithmeticCastable{}
extension CGFloat: ArithmeticCastable{}

extension ArithmeticCastable {
    func cast<R: ArithmeticCastable>() -> R {
        switch self {
        case let n as Int:
            return R(n)
        case let n as Int8:
            return R(n)
        case let n as Int16:
            return R(n)
        case let n as Int32:
            return R(n)
        case let n as Int64:
            return R(n)
        case let n as UInt:
            return R(n)
        case let n as UInt8:
            return R(n)
        case let n as UInt16:
            return R(n)
        case let n as UInt32:
            return R(n)
        case let n as UInt64:
            return R(n)
        case let n as Float:
            return R(n)
        case let n as Double:
            return R(n)
        case let n as CGFloat:
            return R(n)
        default:
            assertionFailure("Couldn't cast to \(String(R.self)) from \(String(self))")
            return R(0)
        }
    }
}
