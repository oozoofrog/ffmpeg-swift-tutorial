//
//  Castable.swift
//  Castable
//
//  Created by jayios on 2016. 6. 23..
//  Copyright © 2016년 ngenii. All rights reserved.
//

import Foundation

protocol Castable {}

protocol UnsafePointerProtocol: NilLiteralConvertible {
    associatedtype Memory
    init(nilLiteral: ())
    init<Memory>(_ from: UnsafeMutablePointer<Memory>)
    init<Memory>(_ from: UnsafePointer<Memory>)
    var memory: Memory { get }
    func mutable<M>() -> UnsafeMutablePointer<M>
}

extension UnsafeMutablePointer : UnsafePointerProtocol, Castable{}
extension UnsafePointer : UnsafePointerProtocol, Castable{}

extension UnsafePointerProtocol where Self: Castable {
    func cast<P: UnsafePointerProtocol, M where M == P.Memory>() -> P {
        switch self {
        case let ptr as UnsafePointer<Memory>:
            return P(ptr)
        case let ptr as UnsafeMutablePointer<Memory>:
            return P(ptr)
        default:
            return nil
        }
    }
    
    func mutable<M>() -> UnsafeMutablePointer<M> {
        switch self {
        case let ptr as UnsafePointer<Memory>:
            return UnsafeMutablePointer<M>(ptr)
        case let ptr as UnsafeMutablePointer<Memory>:
            return UnsafeMutablePointer<M>(ptr)
        default:
            return nil
        }
    }
}


protocol Pointerable {
    associatedtype Element
    var pointer: UnsafePointer<Element> {get}
}

extension Array : Pointerable {}
extension ArraySlice : Pointerable {
    func array() -> Array<Element> {
        return Array<Element>(self)
    }
}

extension Pointerable where Self: SequenceType {
    var pointer: UnsafePointer<Element> {
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