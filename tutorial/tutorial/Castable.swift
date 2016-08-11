//
//  Castable.swift
//  Castable
//
//  Created by jayios on 2016. 6. 23..
//  Copyright © 2016년 ngenii. All rights reserved.
//

import Foundation

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
