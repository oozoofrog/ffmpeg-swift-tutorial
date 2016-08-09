//
//  ViewController.swift
//  tutorial
//
//  Created by jayios on 2016. 8. 8..
//  Copyright © 2016년 gretech. All rights reserved.
//

import UIKit
import SDL
import CuckooAlert

class ViewController: UITableViewController {
    
    let documentPath = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true)[0]
    
    var fd: CInt = 0
    var documents_observer: dispatch_source_t!
    
    var files: [String]?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        defer {
            updateDocuments()
        }
        
        fd = open(documentPath, O_EVTONLY)
        documents_observer = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, UInt(fd), DISPATCH_VNODE_WRITE | DISPATCH_VNODE_DELETE, dispatch_get_main_queue())
        
        weak var weakSelf: ViewController? = self
        dispatch_source_set_event_handler(documents_observer) {
            weakSelf?.updateDocuments()
        }
        dispatch_resume(documents_observer)
    }
    
    deinit {
        if 0 < fd {
            close(fd)
        }
    }
    
    func updateDocuments() {
        
        guard let files = try? NSFileManager.defaultManager().contentsOfDirectoryAtPath(documentPath) else {
            return
        }
        self.files = files.filter(){ file in
            guard let attributes: NSDictionary = try? NSFileManager.defaultManager().attributesOfItemAtPath(documentPath + "/" + file) else {
                return !file.hasPrefix(".")
            }
            return !file.hasPrefix(".") && attributes.fileType() == NSFileTypeRegular
        }
        
        self.tableView.reloadData()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    
    //MARK: - UITableViewDataSource
    
    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return files?.count ?? 0
    }
    
    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier("Cell", forIndexPath: indexPath)
        
        guard let file = self.files?[indexPath.row] else {
            cell.textLabel?.text = nil
            return cell
        }
        
        cell.textLabel?.text = file
        
        return cell
    }
    
    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        guard let file = self.files?[indexPath.row] else {
            return
        }
        
        let path = "\(documentPath)/\(file)"
        
        let sheet = UIAlertController(title: "tutorial", message: nil, preferredStyle: .ActionSheet)
        for index in TutorialIndex.all {
            sheet.addAction(UIAlertAction(title: "\(index)", style: .Default) { _ in
                    index.runTutorial([path])
                })
        }
        
        self.presentViewController(sheet, animated: true) {
            tableView.deselectRowAtIndexPath(indexPath, animated: true)
        }
    }
    
    override func tableView(tableView: UITableView, canEditRowAtIndexPath indexPath: NSIndexPath) -> Bool {
        return true
    }
    
    override func tableView(tableView: UITableView, editActionsForRowAtIndexPath indexPath: NSIndexPath) -> [UITableViewRowAction]? {
        weak var weakSelf: ViewController? = self
        return TutorialIndex.all.lazy.map({
            let index = $0
            return UITableViewRowAction(style: .Default, title: "\(index)", handler: { (action, indexPath) in
                tableView.setEditing(false, animated: true)
                guard let file = weakSelf?.files?[indexPath.row], let documentPath = weakSelf?.documentPath else {
                    return
                }
                let path = "\(documentPath)/\(file)"
                index.runTutorial([path])
            })
        })
    }
}

