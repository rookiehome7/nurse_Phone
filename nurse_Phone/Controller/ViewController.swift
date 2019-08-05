//
//  ViewController.swift
//  bedsiteUnit_Phone
//
//  Created by Takdanai Jirawanichkul on 2/7/2562 BE.
//
import UIKit
import CocoaMQTT
import FilesProvider
import AVFoundation

import CoreLocation
import CoreBluetooth

struct ViewVT{
        static var lct: LinphoneCoreVTable = LinphoneCoreVTable()
}

class ViewController: UIViewController, FileProviderDelegate {
    
    // User Label
    @IBOutlet weak var mqttTopic: UILabel!
    @IBOutlet weak var mqttStatus: UILabel!
    @IBOutlet weak var mqttMessage: UILabel!
    @IBOutlet weak var sipStatus: UILabel!
    
    @IBOutlet weak var phoneNumberField: UITextField!
    // User Button name
    @IBOutlet weak var mqttReconnectButton: UIButton!
    @IBOutlet weak var acceptButton: UIButton!
    @IBOutlet weak var rejectButton: UIButton!
    
    
    // FTP Setting
    let server: URL = URL(string: "ftp://192.168.1.10")!
    let username = "admin"
    let password = ""
    
    var recordingSession: AVAudioSession!
    var audioPlayer: AVAudioPlayer!
    var audioRecorder: AVAudioRecorder!
    
    // Create File Provider
    let documentsProvider = LocalFileProvider()
    var ftpFileProvider : FTPFileProvider?
    
    @IBOutlet weak var playButton: UIButton!
    @IBOutlet weak var recordButton: UIButton!
    
    // Variable decrelation
    let accountData = LocalUserData() // Get function read file from PLIST
    

    
    // iBeacon Broadcast
    var broadcastBeacon: CLBeaconRegion!
    var beaconPeripheralData: NSDictionary!
    var peripheralManager: CBPeripheralManager!
    
    var taskID: String = ""
    var incomingPhoneNumber: String = ""
    var priorityTask: String = ""
    
    override func viewDidLoad() {
        super.viewDidLoad()
        //UI Setting
        mqttReconnectButton.isHidden = false
        mqttMessage.isHidden = true
    
        updateUIStatus()
        hideTaskUI()
        
//        //Run MQTT on mac: /usr/local/sbin/mosquitto -c /usr/local/etc/mosquitto/mosquitto.conf
//        mqttSetting()       // Setting MQTT
//        _ = mqtt!.connect() // MQTT Connect'
        
        // iBeacon Broadcast Signal
        startBroadcastBeacon()
        
    
        // FTP & Local File Setup
        ftpFileProvider?.delegate = self as FileProviderDelegate
        documentsProvider.delegate = self as FileProviderDelegate
        let credential = URLCredential(user: username, password: password, persistence: .permanent)
        ftpFileProvider = FTPFileProvider(baseURL: server, passive: true, credential: credential, cache: nil)
        
        
        
        //UPDATE UI every 2 second
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.updateUIStatus()
        }
        // to register a new notification handler

    }
    
    // Download Record file from FTP Server
    func downloadFTPFile(){
        // Remove file it first
        documentsProvider.removeItem(path: "playback.m4a", completionHandler: nil)
        let localFileURL = getDocumentsDirectory().appendingPathComponent("playback.m4a")
        ftpFileProvider?.copyItem(path: "/recording.m4a", toLocalURL: localFileURL, completionHandler: nil)
    }
    
    // Send Record file to FTP Server
    func uploadRecordFile(){
        let fileURL = getDocumentsDirectory().appendingPathComponent("recording.m4a")
        ftpFileProvider?.copyItem(localFile: fileURL, to: "/recording.m4a", overwrite: true, completionHandler: nil)
    }
    // MARK: UI
    func loadRecordingUI() {
        recordButton.isHidden = false
        recordButton.setTitle("Tap to Record", for: .normal)
    }
    func showTaskUI() {
        acceptButton.isHidden = false
        rejectButton.isHidden = false
        
    }
    func hideTaskUI(){
        acceptButton.isHidden = true
        rejectButton.isHidden = true
        
    }
    
    // MARK: - Action
    @IBAction func recordButtonPressed(_ sender: UIButton) {
        if audioRecorder == nil {
            startRecording()
        } else {
            finishRecording(success: true)
        }
    }
    @IBAction func playButtonPressed(_ sender: Any) {
        if audioPlayer == nil {
            startPlayback()
        } else {
            finishPlayback()
        }
    }
    
    @IBAction func downloadButtonPressed(_ sender: Any) {
        print("DownloadButtonPress")
        downloadFTPFile()
    }
    
    @IBAction func acceptButton(_ sender: Any) {
        //mqtt?.publish("wearable/" + accountData.getSipUsername()! , withString: string )
        // Make Call
        //makeCallMqtt()
        hideTaskUI()
        //testComplete()
        
        
        
    }
    @IBAction func rejectButton(_ sender: Any) {
        //mqtt?.publish("wearable/" + accountData.getSipUsername()!, withString: string )
        hideTaskUI()
    }
    
    
    // MARK: - Recording
    func startRecording() {
        let audioFilename = getDocumentsDirectory().appendingPathComponent("recording.m4a")
        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 12000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder.delegate = self
            audioRecorder.record()
            recordButton.setTitle("Tap to Stop Record", for: .normal)
        } catch {
            finishRecording(success: false)
        }
    }
    func finishRecording(success: Bool) {
        audioRecorder.stop()
        audioRecorder = nil
        if success {
            uploadRecordFile() // Upload to FTP server
            recordButton.setTitle("Tap to Re-record", for: .normal)
            playButton.setTitle("Play Sound", for: .normal)
            playButton.isHidden = false
        }
        else {
            recordButton.setTitle("Tap to Record", for: .normal)
            playButton.isHidden = true
            // recording failed :(
        }
    }
    
    // MARK: - Playback
    func startPlayback() {
        let audioFilename = getDocumentsDirectory().appendingPathComponent("playback.m4a")
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: audioFilename)
            audioPlayer.delegate = self
            audioPlayer.play()
            playButton.setTitle("Stop Playback", for: .normal)
        } catch {
            //playButton.isHidden = true
            // unable to play recording!
        }
    }
    func finishPlayback() {
        audioPlayer = nil
        playButton.setTitle("Play Sound", for: .normal)
    }
    

    // Function to update UI
    func updateUIStatus(){
        
        if sipRegistrationStatus == .fail {
            sipStatus.text = "FAIL"
        }
        else if sipRegistrationStatus == .unknown {
            sipStatus.text = "Unknown"
        }
        else if sipRegistrationStatus ==  .ok {
            sipStatus.text = "OK"
        }
        else if sipRegistrationStatus == .unregister{
            sipStatus.text = "Not Register"
        }
        else if sipRegistrationStatus == .progress{
            sipStatus.text = "Progress"
        }
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    // MARK : Action
    @IBAction func mqttReconnectButton(_ sender: Any) {
        //_ = mqtt!.connect()
    }

    override func viewWillAppear(_ animated: Bool) {
        // Reset after view appear
        //_ = mqtt?.disconnect()
        //mqttSetting()
        //_ = mqtt?.connect()
        mqttTopic.text! = accountData.getMQTTTopic()! + "/" + accountData.getSipUsername()!
    }
    
    override func viewDidDisappear(_ animated: Bool) {
    }
    
    // Send phone number  to OutgoingCallViewController
    // Identifier : makeCall
    // Get number from text field
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "makeCall"
        {
            if let destinationVC = segue.destination as? OutgoingCallViewController {
                destinationVC.phoneNumber = phoneNumberField.text
            }
        }
    }
    
    // FileProvider Function
    func fileproviderSucceed(_ fileProvider: FileProviderOperations, operation: FileOperationType) {
        switch operation {
        case .copy(source: let source, destination: let dest):
            print("\(source) copied to \(dest).")
        case .remove(path: let path):
            print("\(path) has been deleted.")
        default:
            if let destination = operation.destination {
                print("\(operation.actionDescription) from \(operation.source) to \(destination) succeed.")
            } else {
                print("\(operation.actionDescription) on \(operation.source) succeed.")
            }
        }
    }
    
    func fileproviderFailed(_ fileProvider: FileProviderOperations, operation: FileOperationType, error: Error) {
        switch operation {
        case .copy(source: let source, destination: let dest):
            print("copying \(source) to \(dest) has been failed.")
        case .remove:
            print("file can't be deleted.")
        default:
            if let destination = operation.destination {
                print("\(operation.actionDescription) from \(operation.source) to \(destination) failed.")
            } else {
                print("\(operation.actionDescription) on \(operation.source) failed.")
            }
        }
    }
    
    func fileproviderProgress(_ fileProvider: FileProviderOperations, operation: FileOperationType, progress: Float) {
        switch operation {
        case .copy(source: let source, destination: let dest) where dest.hasPrefix("file://"):
            print("Downloading \(source) to \((dest as NSString).lastPathComponent): \(progress * 100) completed.")
        case .copy(source: let source, destination: let dest) where source.hasPrefix("file://"):
            print("Uploading \((source as NSString).lastPathComponent) to \(dest): \(progress * 100) completed.")
        case .copy(source: let source, destination: let dest):
            print("Copy \(source) to \(dest): \(progress * 100) completed.")
        default:
            break
        }
    }
}

// MARK: iBeacon - View Controller Extension Part
extension ViewController: CBPeripheralManagerDelegate {
    // MARK: iBeacon Broadcast Signal
    func startBroadcastBeacon() {
        if broadcastBeacon != nil {
            stopBroadcastBeacon()
        }
        // Set iBeacon Value
        let uuid = UUID(uuidString: accountData.getBeaconUUID()!)!
        let localBeaconMajor: CLBeaconMajorValue = UInt16(accountData.getBeaconMajor()!)!
        let localBeaconMinor: CLBeaconMinorValue = UInt16(accountData.getBeaconMinor()!)!
        //let localBeaconMajor: CLBeaconMajorValue = 123
        //let localBeaconMinor: CLBeaconMinorValue = 789
        let identifier = "Put your identifier here"
        
        broadcastBeacon = CLBeaconRegion(proximityUUID: uuid, major: localBeaconMajor, minor: localBeaconMinor, identifier: identifier)
        beaconPeripheralData = broadcastBeacon.peripheralData(withMeasuredPower: nil)
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: nil)
    }
    func stopBroadcastBeacon() {
        peripheralManager.stopAdvertising()
        peripheralManager = nil
        beaconPeripheralData = nil
        broadcastBeacon = nil
    }
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            peripheralManager.startAdvertising(beaconPeripheralData as? [String: Any])
        }
        else if peripheral.state == .poweredOff {
            peripheralManager.stopAdvertising()
        }
    }
}





extension ViewController: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            finishRecording(success: false)
        }
    }
    
}

extension ViewController: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        finishPlayback()
    }
}

