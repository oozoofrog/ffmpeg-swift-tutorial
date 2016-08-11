//
//  AppDelegate.swift
//  tutorial
//
//  Created by jayios on 2016. 8. 8..
//  Copyright © 2016년 gretech. All rights reserved.
//

import UIKit
import ffmpeg

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?


    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
        // Override point for customization after application launch.
        
        av_register_all()
        avfilter_register_all()
        
        let documentPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let documentSamplePath = "\(documentPath)/sample.mp4"
        if false == FileManager.default.fileExists(atPath: documentSamplePath) {
            guard let samplePath = Bundle.main.path(forResource: "sample", ofType: "mp4") else {
                return true
            }
            do {
                try FileManager.default.copyItem(atPath: samplePath, toPath: documentSamplePath)
            } catch let err as NSError {
                assertionFailure(err.localizedDescription)
            }
        }
        
        #if arch(i386) || arch(x86_64)
            self.createSymbolickLinkForDocuments()
        #endif
//        let nomore = NSUserDefaults.standardUserDefaults().boolForKey("NO_MORE_ALERT")
//        if nomore {
//            return true
//        }
//        
//        if NSFileManager.defaultManager().fileExistsAtPath(self.documentPathForUserWithAppName) && self.docPath == (try? NSFileManager.defaultManager().destinationOfSymbolicLinkAtPath(self.documentPathForUserWithAppName) ?? "") {
//            return true
//        }
//        print(NSFileManager.defaultManager().fileExistsAtPath(self.documentPathForUserWithAppName))
//        print((try? NSFileManager.defaultManager().destinationOfSymbolicLinkAtPath(self.documentPathForUserWithAppName) ?? ""))
//        print(self.docPath)
//        dispatch_async(dispatch_get_main_queue()) {
//            let alert = UIAlertController(title: "Ask", message: "Allow documents symbolic link to \(self.documentPathForUserWithAppName) folder (only simulator)", preferredStyle: .Alert)
//            alert.addAction(UIAlertAction(title: "Confirm", style: .Default, handler: { (action) in
//                self.createSymbolickLinkForDocuments()
//            }))
//            alert.addAction(UIAlertAction(title: "Do not allow", style: .Cancel, handler: nil))
//            
//            alert.addAction(UIAlertAction(title: "Do not allow and No More This Alert", style: .Destructive, handler: { (action) in
//                NSUserDefaults.standardUserDefaults().setBool(true, forKey: "NO_MORE_ALERT")
//                NSUserDefaults.standardUserDefaults().synchronize()
//            }))
//            
//            self.window?.rootViewController?.presentViewController(alert, animated: true, completion: nil)
//        }
//        
        return true
    }
    
    var docPath: NSString {
        return NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
    }
    var docPaths: [String] {
        return docPath.components(separatedBy: "/")
    }
    var user: String {
        return docPaths[2]
    }
    var documentPathForUser: String {
        return docPaths[0...2].joined(separator: "/") + "/Documents"
    }
    
    var documentPathForUserWithAppName: String {
        return documentPathForUser + "/ffmpeg_tutorial"
    }
    
    func createSymbolickLinkForDocuments() {
        if FileManager.default.fileExists(atPath: self.documentPathForUserWithAppName) {
            return
        }
        do {
            try FileManager.default.removeItem(atPath: self.documentPathForUserWithAppName)
            try FileManager.default.createSymbolicLink(atPath: self.documentPathForUserWithAppName, withDestinationPath: self.docPath as String)
            let noti = UIAlertController(title: "Succeed", message: "Symbolic link of \(self.docPath) make to \(self.documentPathForUserWithAppName)", preferredStyle: .alert)
            noti.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil))
            self.window?.rootViewController?.present(noti, animated: true, completion: nil)
        } catch let err as NSError {
            assertionFailure(err.localizedDescription)
        }
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }


}

