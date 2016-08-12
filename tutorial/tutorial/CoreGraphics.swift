//
//  CoreGraphics.swift
//  tutorial
//
//  Created by Kwanghoon Choi on 2016. 8. 14..
//  Copyright © 2016년 gretech. All rights reserved.
//

import Foundation
import CoreGraphics
import AVFoundation

protocol CGSizeable {
    var width: CGFloat { get }
    var height: CGFloat { get }
}

protocol CGPointable {
    var origin: CGPoint { get }
}

protocol CGRationable {
    var ratio: CGFloat { get }
}

extension CGSize: CGRationable {}
extension CGRect: CGRationable {}

extension CGRationable where Self: CGSizeable {
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
