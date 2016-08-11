//
//  ViewController.swift
//  tutorial
//
//  Created by jayios on 2016. 8. 8..
//  Copyright © 2016년 gretech. All rights reserved.
//

import UIKit
import SDL

class ViewController: UITableViewController {
    
    let documentPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
    
    var fd: CInt = 0
    var documents_observer: DispatchSourceFileSystemObject?
    
    var files: [String]?
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        defer {
            updateDocuments()
        }
        
        fd = open(documentPath, O_EVTONLY)
        documents_observer = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete], queue: .main)
        
        weak var weakSelf: ViewController? = self
        documents_observer?.setEventHandler {
            weakSelf?.updateDocuments()
        }
        documents_observer?.resume()
    }
    
    deinit {
        if 0 < fd {
            close(fd)
        }
    }
    
    func updateDocuments() {
        
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: documentPath) else {
            return
        }
        self.files = files.filter(){ file in
            guard let attributes: NSDictionary = try? FileManager.default.attributesOfItem(atPath: documentPath + "/" + file) else {
                return !file.hasPrefix(".")
            }
            return !file.hasPrefix(".") && attributes.fileType() == FileAttributeType.typeRegular.rawValue
        }
        
        self.tableView.reloadData()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    
    //MARK: - UITableViewDataSource
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return files?.count ?? 0
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        
        guard let file = self.files?[(indexPath as NSIndexPath).row] else {
            cell.textLabel?.text = nil
            return cell
        }
        
        cell.textLabel?.text = file
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let file = self.files?[(indexPath as NSIndexPath).row] else {
            return
        }
        
        let path = "\(documentPath)/\(file)"
        
        let sheet = UIAlertController(title: "tutorial", message: nil, preferredStyle: .actionSheet)
        for index in TutorialIndex.all {
            sheet.addAction(UIAlertAction(title: "\(index)", style: .default) { _ in
                    index.runTutorial([path])
                })
        }
        sheet.popoverPresentationController?.sourceView = tableView
        sheet.popoverPresentationController?.sourceRect = tableView.rectForRow(at: indexPath)
        self.present(sheet, animated: true) {
            tableView.deselectRow(at: indexPath, animated: true)
        }
    }
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    override func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        weak var weakSelf: ViewController? = self
        return TutorialIndex.all.lazy.map({
            let index = $0
            return UITableViewRowAction(style: .default, title: "\(index)", handler: { (action, indexPath) in
                tableView.setEditing(false, animated: true)
                guard let file = weakSelf?.files?[(indexPath as NSIndexPath).row], let documentPath = weakSelf?.documentPath else {
                    return
                }
                let path = "\(documentPath)/\(file)"
                index.runTutorial([path])
            })
        })
    }
}

