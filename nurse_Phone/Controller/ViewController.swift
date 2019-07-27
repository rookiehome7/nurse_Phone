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
    var mqtt: CocoaMQTT?
    let accountData = LocalUserData() // Get function read file from PLIST
    
    // iBeacon Broadcast
    var broadcastBeacon: CLBeaconRegion!
    var beaconPeripheralData: NSDictionary!
    var peripheralManager: CBPeripheralManager!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        //UI Setting
        mqttReconnectButton.isHidden = false
        mqttMessage.isHidden = true
    
        updateUIStatus()
        
        //Run MQTT on mac: /usr/local/sbin/mosquitto -c /usr/local/etc/mosquitto/mosquitto.conf
        mqttSetting()       // Setting MQTT
        _ = mqtt!.connect() // MQTT Connect'
        
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
    
    func loadRecordingUI() {
        recordButton.isHidden = false
        recordButton.setTitle("Tap to Record", for: .normal)
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
        mqttTopic.text = accountData.getMQTTTopic()! + "/" + accountData.getSipUsername()!
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
        _ = mqtt!.connect()
        mqttTopic.text = accountData.getMQTTTopic()! + "/" + accountData.getSipUsername()!
    }

    override func viewWillAppear(_ animated: Bool) {
        // Reset after view appear
        _ = mqtt?.disconnect()
        mqttSetting()
        _ = mqtt?.connect()
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


// Cocoa MQTT - View Controller Extension Part
// This extension will handle all MQTT function
extension ViewController: CocoaMQTTDelegate {
    
    func makeCall(phoneNumber : String){
        let vc = UIStoryboard.init(name: "Main", bundle: Bundle.main).instantiateViewController(withIdentifier: "OutgoingCallViewController") as? OutgoingCallViewController
        vc!.phoneNumber = phoneNumber
        //self.navigationController?.pushViewController(vc!, animated: true)
        self.present(vc!, animated: true, completion: nil)
    }
    
    func terminateCall(){
        let call = linphone_core_get_current_call(theLinphone.lc!)
        if call != nil {
            let result = linphone_core_terminate_call(theLinphone.lc!, call)
            NSLog("Terminated call result(outgoing): \(result)")
        }
        OutgoingCallViewData.controller?.dismiss(animated: false, completion: nil)
    }
    
    //MARK : SETTING Environment
    func mqttSetting() {
        // Get MQTT Broker IP from PLIST File
        let brokerIP = accountData.getMQTTServerIp()!
        let clientID = "CocoaMQTT-" + String(ProcessInfo().processIdentifier)
        mqtt = CocoaMQTT(clientID: clientID, host: brokerIP, port: 1883)
        mqtt!.username = ""
        mqtt!.password = ""
        mqtt!.willMessage = CocoaMQTTWill(topic: "/will", message: "dieout")
        mqtt!.keepAlive = 60
        mqtt!.delegate = self
    }
    
    //MARK : MQTT Command handle
    // When received message
    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16 ) {
        TRACE("message: \(message.string.description), id: \(id)")
        mqttMessage.isHidden = false
        mqttMessage.text = message.string?.description
        let command = message.string!.components(separatedBy: " ")
        if command[0] == "call" {
            makeCall(phoneNumber: command[1])
        }
        else if command[0] == "end" {
            terminateCall()
        }
        else if command[0] == "task" {
            
            // Assume Nurse answer
            // Publish message : task 'bedsitenumber' accept
            // And then make call
            makeCall(phoneNumber: command[1])
        }
            
            
            
//        else if command[0] == "play"{
//            if audioPlayer == nil {
//                startPlayback()
//            } else {
//                finishPlayback()
//            }
//        }
//        else if command[0] == "update"{
//            downloadFTPFile()
//        }
//        else if command[0] == "record"{
//            if audioRecorder == nil {
//                startRecording()
//            } else {
//                finishRecording(success: true)
//            }
//        }
    }
    
    // When MQTT Server Connect
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        TRACE("ack: \(ack)")
        if ack == .accept {
            mqttReconnectButton.isHidden = true
            // Get MQTT Broker Topic from PLIST File
            let mqttTopic = accountData.getMQTTTopic()! + "/" + accountData.getSipUsername()!
            mqtt.subscribe(mqttTopic, qos: CocoaMQTTQOS.qos2)
            mqttStatus.text = "Connected " + accountData.getMQTTServerIp()!
        }
    }
    
    // When MQTT Server Disconnect
    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        TRACE("\(err.debugDescription)")
        mqttReconnectButton.isHidden = false
        mqttStatus.text = "Disconnect"
        // Try to disconnect every 5 seconds when MQTT server Disconnect
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            _ = mqtt.connect()
        }
    }
    

    func mqtt(_ mqtt: CocoaMQTT, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Void) {
        TRACE("trust: \(trust)")
        completionHandler(true)
    }
    
    
    func mqtt(_ mqtt: CocoaMQTT, didStateChangeTo state: CocoaMQTTConnState) {
        TRACE("new state: \(state)")
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {
        TRACE("message: \(message.string.description), id: \(id)")
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {
        TRACE("id: \(id)")
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopic topics: [String]) {
        TRACE("topics: \(topics)")
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopic topic: String) {
        TRACE("topic: \(topic)")
    }
    
    func mqttDidPing(_ mqtt: CocoaMQTT) {
        TRACE()
    }
    
    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {
        TRACE()
    }
    

}

extension ViewController {
    func TRACE(_ message: String = "", fun: String = #function) {
        let names = fun.components(separatedBy: ":")
        var prettyName: String
        if names.count == 2 {
            prettyName = names[0]
        } else {
            prettyName = names[1]
        }
        if fun == "mqttDidDisconnect(_:withError:)" {
            prettyName = "didDisconect"
        }
        print("[TRACE] [\(prettyName)]: \(message)")
    }
}

extension Optional {
    // Unwarp optional value for printing log only
    var description: String {
        if let warped = self {
            return "\(warped)"
        }
        return ""
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

