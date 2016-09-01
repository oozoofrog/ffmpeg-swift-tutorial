//
//  TableViewController.swift
//  SwiftPlayer
//
//  Created by jayios on 2016. 9. 1..
//  Copyright © 2016년 Kwanghoon Choi. All rights reserved.
//

import UIKit

class TableViewController: UITableViewController {

    
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
        
        weak var weakSelf: TableViewController? = self
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
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: documentPath + "/" + file) else {
                return false
            }
            guard let type = attributes[.type] as? String else {
                return false
            }
            
            return !file.hasPrefix(".") && type == FileAttributeType.typeRegular.rawValue
        }
        
        self.tableView.reloadData()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let files = self.files, 0 < files.count, let viewController = segue.destination as? ViewController, let selectedPath = self.tableView.indexPathForSelectedRow {
            viewController.path = documentPath + "/\(files[selectedPath.row])"
        }
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
}
