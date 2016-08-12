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

protocol CGSizeStructure {
    var width: CGFloat { get }
    var height: CGFloat { get }
}

protocol CGPointStructure {
    var x: CGFloat { get }
    var y: CGFloat { get }
}

protocol CGRectStructure {
    var origin: CGPoint { get }
    var size: CGSize { get }
}

extension CGSize: CGSizeStructure {}
extension CGRect: CGSizeStructure, CGPointStructure, CGRectStructure {}

extension CGPointStructure where Self: CGRectStructure {
    var x: CGFloat {
        return self.origin.x
    }
    var y: CGFloat {
        return self.origin.y
    }
}

protocol CGRationable {
    var ratio: CGFloat { get }
}

extension CGSize: CGRationable {}
extension CGRect: CGRationable {}

extension CGRationable where Self: CGSizeStructure {
    var ratio: CGFloat {
        return self.width / self.height
    }
}

extension CGRect {
    func aspectFit(aspectRatio: CGSize) -> CGRect {
        return AVMakeRect(aspectRatio: aspectRatio, insideRect: self)
    }
    func aspectFill(aspectRatio: CGSize) -> CGRect {
        let scale = aspectRatio.ratio / self.ratio
        
        return self.applying(CGAffineTransform(scaleX: scale, y: scale))
    }
}

protocol SDLCastable {
    var SDL: SDL_Rect { get }
    var rect: CGRect { get }
}

protocol SDLStructure {
    var x: Int32 { get }
    var y: Int32 { get }
    var w: Int32 { get }
    var h: Int32 { get }
}

extension CGSize: SDLCastable{}
extension CGRect: SDLCastable{}
extension SDL_Rect: SDLStructure, SDLCastable{}

extension SDLCastable where Self: SDLStructure {
    var SDL: SDL_Rect {
        return self as! SDL_Rect
    }
    var rect: CGRect {
        return CGRect(x: Int(x), y: Int(y), width: Int(w), height: Int(h))
    }
}

extension SDLCastable where Self: CGSizeStructure {
    var SDL: SDL_Rect {
        return SDL_Rect(x: 0, y: 0, w: width.cast(), h: height.cast())
    }
    var rect: CGRect {
        return CGRect(x: 0, y: 0, width: width, height: height)
    }
}

extension SDLCastable where Self: CGPointStructure, Self: CGSizeStructure {
    var SDL: SDL_Rect {
        return SDL_Rect(x: x.cast(), y: y.cast(), w: width.cast(), h: height.cast())
    }
    var rect: CGRect {
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

extension AVCodecContext {
    var size: CGSize {
        var size = CGSize()
        size.width = self.width.cast()
        size.height = self.height.cast()
        return size
    }
}
