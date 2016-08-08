//
//  tutorial1.swift
//  tutorial
//
//  Created by jayios on 2016. 8. 8..
//  Copyright © 2016년 gretech. All rights reserved.
//

import Foundation
import ffmpeg

enum TutorialIndex {
    case tutorial1
    
    static let all: [TutorialIndex] = [.tutorial1]
}

class Tutorial {
    init(tutorialIndex index: TutorialIndex, paths:[String]) {
        switch index {
        case .tutorial1:
            self.tutorial1(paths[0])
        }
    }
    
    func tutorial1(path: String) {
        
    }
}