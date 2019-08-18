//
//  MainViewController.swift
//  nurseUnit_Device
//
//  Created by Takdanai Jirawanichkul on 5/8/2562 BE.
//
import UIKit
import CocoaMQTT
import MediaPlayer
import AVFoundation
import CoreLocation
import CoreBluetooth
import FilesProvider

struct MainViewData{
    static var controller: MainViewController?
}

struct MainViewVT{
    static var lct: LinphoneCoreVTable = LinphoneCoreVTable()
}

var mainViewCallStateChanged: LinphoneCoreCallStateChangedCb = {
    (lc: Optional<OpaquePointer>, call: Optional<OpaquePointer>, callSate: LinphoneCallState,  message: Optional<UnsafePointer<Int8>>) in
    switch callSate{
    case LinphoneCallIncomingReceived: /**<This is a new incoming call */
        NSLog("mainViewCallStateChanged: LinphoneCallIncomingReceived")
        // Auto Answer Call
        let address = linphone_call_get_remote_address_as_string(call)!
        MainViewData.controller?.incomingCallLabel.text = getPhoneNumberFromAddress(String(cString: address))
        MainViewData.controller?.callStatusLabel.text = "IncomingReceived"
        // Auto answer
        MainViewData.controller?.answerCall()
        //MainViewData.controller?.answerButton.isHidden = false
        MainViewData.controller?.callMode_Active()
        
    case LinphoneCallOutgoingProgress:
        NSLog("mainViewCallStateChanged: LinphoneCallOutgoingProgress")
        MainViewData.controller?.callStatusLabel.text = "Calling Progress"
        MainViewData.controller?.answerButton.isHidden = true
        MainViewData.controller?.callMode_Active()
        
    case LinphoneCallConnected:
        NSLog("mainViewCallStateChanged: LinphoneCallConnected")
        MainViewData.controller?.callStatusLabel.text = "Connected"
        MainViewData.controller?.answerButton.isHidden = true
        MainViewData.controller?.callMode_Active()
        if MainViewData.controller?.audioPlayer != nil {
            MainViewData.controller?.finishPlayback()
        }
        MainViewData.controller?.startSearchingBeacon()
        
    case LinphoneCallError:
        NSLog("mainViewCallStateChanged: LinphoneCallError")
        MainViewData.controller?.callStatusLabel.text = "Error"
        MainViewData.controller?.terminateCall()
        MainViewData.controller?.stopSearchingBeacon()
        
    case LinphoneCallEnd:
        NSLog("mainViewCallStateChanged: LinphoneCallEnd")
        MainViewData.controller?.callStatusLabel.text = "End"
        MainViewData.controller?.terminateCall()
        MainViewData.controller?.stopSearchingBeacon()
        
        
    case LinphoneCallReleased:
        NSLog("mainViewCallStateChanged: LinphoneCallReleased")
        MainViewData.controller?.callStatusLabel.text = "Released"
        MainViewData.controller?.terminateCall()
        MainViewData.controller?.stopSearchingBeacon()
        
    default:
        NSLog("mainViewCallStateChanged: Default call state \(callSate)")
    }
}

class MainViewController: UIViewController {
    
    // Button
    @IBOutlet weak var callButton: UIButton!
    @IBOutlet weak var endButton: UIButton!
    @IBOutlet weak var answerButton: UIButton!
    
    
    @IBOutlet weak var acceptTaskButton: UIButton!
    @IBOutlet weak var rejectTaskButton: UIButton!
    
    @IBOutlet weak var mqttReconnectButton: UIButton!
    
    @IBOutlet weak var warningSoundButton: UIButton!
    
    // Text Field
    @IBOutlet weak var phoneNumberTextField: UITextField!
    
    // Label
    @IBOutlet weak var incomingCallLabel: UILabel!
    @IBOutlet weak var callStatusLabel: UILabel!

    
    @IBOutlet weak var mqttSubscribeTopicLabel: UILabel!
    @IBOutlet weak var mqttMessageLabel: UILabel!
    @IBOutlet weak var mqttStatusLabel: UILabel!
    
    @IBOutlet weak var sipPhoneNumberLabel: UILabel!
    @IBOutlet weak var sipStatusLabel: UILabel!
    @IBOutlet weak var sipServerIpLabel: UILabel!
    
    @IBOutlet weak var beaconRSSILabel: UILabel!
    @IBOutlet weak var beaconProximityLabel: UILabel!
    
    @IBOutlet weak var beaconSearchStatusLabel: UILabel!
    @IBOutlet weak var beaconBroadcastStatusLabel: UILabel!
    
    // MQTT
    var audioPlayer: AVAudioPlayer!

    // Call Class
    let soundManager = SoundManager()
    let accountData = LocalUserData()
    
    // iBeacon Searching
    var locationManager: CLLocationManager!
    // iBeacon Broadcast
    var broadcastBeacon: CLBeaconRegion!
    var beaconPeripheralData: NSDictionary!
    var peripheralManager: CBPeripheralManager!
    
    var taskID: String = ""
    var bedsidePhoneNumber: String = ""
    var priorityTask: String = ""
    
    //let vc = VolumeControl.sharedInstance
    
    
    // Create File Provider
    let documentsProvider = LocalFileProvider()
    var ftpFileProvider : FTPFileProvider?
    // FTP Setting
    let server: URL = URL(string: "ftp://192.168.1.10")!
    let username = "admin"
    let password = ""
    

    
    override func viewDidLoad() {
        super.viewDidLoad()
        MainViewData.controller = self

        // iBeacon Searching
        locationManager = CLLocationManager()
        locationManager.delegate = self
        // Dont forgot to add in Info.plst file
        // Privacy - Location When In Use Usage Description & Location Always Usage Description
        locationManager.requestWhenInUseAuthorization()
        locationManager.requestAlwaysAuthorization()
        
        startBroadcastBeacon()
        
        // FTP & Local File Setup
        ftpFileProvider?.delegate = self as FileProviderDelegate
        documentsProvider.delegate = self as FileProviderDelegate
        let credential = URLCredential(user: username, password: password, persistence: .permanent)
        ftpFileProvider = FTPFileProvider(baseURL: server, passive: true, credential: credential)
        //ftpFileProvider = FTPFileProvider(baseURL: server, passive: true, credential: credential, cache: nil)
        

       
        // UPDATE UI every 2 second
         callMode_NotActive()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.updateUI()
        }
        taskAccept_Hide()
    }
    
    // MARK: UserInterface
    func updateUI(){
        print("UpdateUI")
        // SIP Update Value
        sipPhoneNumberLabel.text = accountData.getSipUsername()
        sipServerIpLabel.text = accountData.getSipServerIp()
        switch sipRegistrationStatus{
        case .fail:
            sipStatusLabel.text = "FAIL"
        case .unknown:
            sipStatusLabel.text = "Unknown"
        case .progress:
            sipStatusLabel.text = "Progress"
        case .ok:
            sipStatusLabel.text = "OK"
        case .unregister:
            sipStatusLabel.text = "Not Register"
        }
    }
    
    func callMode_Active(){
        // Hide Call Button
        phoneNumberTextField.isHidden = true
        callButton.isHidden = true
        
        // Show Phone Control UI
        incomingCallLabel.isHidden = false
        callStatusLabel.isHidden = false
        endButton.isHidden = false
        
    }
    func callMode_NotActive(){
        incomingCallLabel.text = "phonenumber"
        
        // Show Call Button
        phoneNumberTextField.isHidden = false
        callButton.isHidden = false
        // Hide Phone Control UI
        incomingCallLabel.isHidden = true
        callStatusLabel.isHidden = true
        endButton.isHidden = true
        answerButton.isHidden = true
    }
    
    func taskAccept_Show() {
        acceptTaskButton.isHidden = false
        rejectTaskButton.isHidden = false
        incomingCallLabel.isHidden = false
        callStatusLabel.isHidden = false
        
        incomingCallLabel.text = bedsidePhoneNumber
        callStatusLabel.text = priorityTask + "_risk_task ID:" + taskID

    }
    
    func taskAccept_Hide(){
        acceptTaskButton.isHidden = true
        rejectTaskButton.isHidden = true
        incomingCallLabel.isHidden = true
        callStatusLabel.isHidden = true
    }
    
    
    // MARK: ViewAppear / ViewDisappear
    override func viewWillAppear(_ animated: Bool) {
        //Add Call Status Listener
        MainViewVT.lct.call_state_changed = mainViewCallStateChanged
        linphone_core_add_listener(theLinphone.lc!,  &MainViewVT.lct)
        
        mqttSubscribeTopicLabel.text = accountData.getMQTTTopic()! + "/" + accountData.getSipUsername()!
        mqttStatusLabel.text = "Connected to " + accountData.getMQTTServerIp()!
        

        theMQTT.manager?.login_PublishMessage(nurseID: accountData.getSipUsername()!, deviceName: "Nurse: " + accountData.getSipUsername()!)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        //Remove Call Status Listener
        linphone_core_remove_listener(theLinphone.lc!, &MainViewVT.lct)
        theMQTT.manager?.logout_PublishMessage(nurseID: accountData.getSipUsername()!, deviceName: "Nurse: " + accountData.getSipUsername()!)
    }
    
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    @IBAction func mqttReconnectButton(_ sender: Any) {

    }

    
    @IBAction func makeCallButton(_ sender: Any) {
        incomingCallLabel.text = phoneNumberTextField.text
        makeCall(phoneNumber : phoneNumberTextField.text!)
    }
    
    @IBAction func answerCallButton(_ sender: Any) {
        answerCall()
    }
    
    @IBAction func endCallButton(_ sender: Any) {
        terminateCall()
        // Publish Message : Task Complete
        taskComplete()
    }
    
    @IBAction func acceptTaskButton(_ sender: Any) {
        // Publish Message
        theMQTT.manager?.acceptTask_PublishMessage(priorityTask: priorityTask, taskID: taskID, bedID: bedsidePhoneNumber, nurseID: accountData.getSipUsername()!)
        // Set UI
        taskAccept_Hide()
        
        // Make Call
        makeCall(phoneNumber: bedsidePhoneNumber)
    }
    
    @IBAction func rejectTaskButton(_ sender: Any) {
        // Publish Message
        theMQTT.manager?.rejectTask_PublishMessage(priorityTask: priorityTask, taskID: taskID, bedID: bedsidePhoneNumber, nurseID: accountData.getSipUsername()!)
       // Set UI
        taskAccept_Hide()
    }
    
    
    func taskComplete(){
        // Publish Message
        theMQTT.manager?.finishTask_PublishMessage(priorityTask: priorityTask, taskID: taskID, bedID: bedsidePhoneNumber, nurseID: accountData.getSipUsername()!, patient_intention: "yes" )
    }
    
    
    @IBAction func playSoundButton(_ sender: Any) {
        if audioPlayer == nil {
            startPlayback()
        }
        else {
            finishPlayback()
        }
    }
}

// MARK : Linphone Extension
extension MainViewController {
    func makeCall(phoneNumber : String){
        // MAKE Phone call
        let lc = theLinphone.lc
        linphone_core_invite(lc, phoneNumber)
    }
    func answerCall(){
        let call = linphone_core_get_current_call(theLinphone.lc!)
        if call != nil {
            let result = linphone_core_accept_call(theLinphone.lc!, call)
            NSLog("Answer call result(receive): \(result)")
        }
    }
    func terminateCall(){
        let call = linphone_core_get_current_call(theLinphone.lc!)
        if call != nil {
            let result = linphone_core_terminate_call(theLinphone.lc!, call)
            NSLog("Terminated call result(receive): \(result)")
        }
        callMode_NotActive()
    }
}



extension MainViewController: FileProviderDelegate {
    
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




// MARK : Sound Extension
extension MainViewController {
    func startPlayback() {
        let audioFilename = getDocumentsDirectory().appendingPathComponent("waitingsound.m4a")
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: audioFilename)
            audioPlayer.delegate = self
            // NumberofLoops: -1 Forever loop
            audioPlayer.numberOfLoops = -1
            audioPlayer.play()
            warningSoundButton.setTitle("Stop Playback", for: .normal)
        } catch {
            warningSoundButton.isHidden = true
            // unable to play recording!
        }
    }
    
    func finishPlayback() {
        audioPlayer = nil
        warningSoundButton.setTitle("Playback", for: .normal)
    }
    
}


extension MainViewController: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        finishPlayback()
    }
}

// MARK: iBeacon - View Controller Extension Part
extension MainViewController: CLLocationManagerDelegate, CBPeripheralManagerDelegate {
    // MARK: iBeacon Broadcast Signal
    func startBroadcastBeacon() {
        beaconBroadcastStatusLabel.text = "Start"
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
        if broadcastBeacon != nil {
            beaconBroadcastStatusLabel.text = "Stop"
            beaconRSSILabel.text = " "
            beaconProximityLabel.text = " "
            peripheralManager.stopAdvertising()
            peripheralManager = nil
            beaconPeripheralData = nil
            broadcastBeacon = nil
        }
    }
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            peripheralManager.startAdvertising(beaconPeripheralData as? [String: Any])
        }
        else if peripheral.state == .poweredOff {
            peripheralManager.stopAdvertising()
        }
    }
    
    // MARK: iBeacon Searching Signal
    func startSearchingBeacon() {
        beaconSearchStatusLabel.text = "Start"
        if let uuid = NSUUID(uuidString: accountData.getBeaconUUID()!) {
            print("Start Monitoring")
            let beaconRegion = CLBeaconRegion(proximityUUID: uuid as UUID, identifier: "iBeacon")
            startMonitoring(beaconRegion: beaconRegion)
            startRanging(beaconRegion: beaconRegion)
        }
    }
    func stopSearchingBeacon() {
        beaconSearchStatusLabel.text = "Stop"
        if let uuid = NSUUID(uuidString: accountData.getBeaconUUID()!) {
            print("Stop Monitoring")
            let beaconRegion = CLBeaconRegion(proximityUUID: uuid as UUID, identifier: "iBeacon")
            stopMonitoring(beaconRegion: beaconRegion)
            stopRanging(beaconRegion: beaconRegion)
        }
        beaconRSSILabel.text = " "
        beaconProximityLabel.text = " "
    }
    
    private func locationManager(manager: CLLocationManager, didChangeAuthorizationStatus status: CLAuthorizationStatus) {
        if !(status == .authorizedAlways || status == .authorizedWhenInUse) {
            print("Must allow location access for this application to work")
        } else {
            if let uuid = NSUUID(uuidString: accountData.getBeaconUUID()!) {
                let beaconRegion = CLBeaconRegion(proximityUUID: uuid as UUID, identifier: "iBeacon")
                startMonitoring(beaconRegion: beaconRegion)
                startRanging(beaconRegion: beaconRegion)
            }
        }
    }
    func startMonitoring(beaconRegion: CLBeaconRegion) {
        beaconRegion.notifyOnEntry = true
        beaconRegion.notifyOnExit = true
        locationManager.startMonitoring(for: beaconRegion)
    }
    func startRanging(beaconRegion: CLBeaconRegion) {
        locationManager.startRangingBeacons(in: beaconRegion)
    }
    func stopMonitoring(beaconRegion: CLBeaconRegion) {
        beaconRegion.notifyOnEntry = false
        beaconRegion.notifyOnExit = false
        locationManager.stopMonitoring(for: beaconRegion)
    }
    func stopRanging(beaconRegion: CLBeaconRegion) {
        locationManager.stopRangingBeacons(in: beaconRegion)
    }
    //  ======== CLLocationManagerDelegate methods ==========
    func locationManager(_ manager: CLLocationManager, didRangeBeacons beacons: [CLBeacon], in region: CLBeaconRegion) {
        for beacon in beacons {
            var beaconProximity: String;
            switch (beacon.proximity) {
            case .unknown:    beaconProximity = "Unknown";
            case .far:        beaconProximity = "Far";
            case .near:       beaconProximity = "Near";
            case .immediate:  beaconProximity = "Immediate";
            default:          beaconProximity = "Error";
            }
            print("BEACON RANGED: uuid: \(beacon.proximityUUID.uuidString) major: \(beacon.major)  minor: \(beacon.minor) proximity: \(beaconProximity)" )
            let call = linphone_core_get_current_call(theLinphone.lc!)
            let address = linphone_call_get_remote_address_as_string(call)!
            let incomingPhoneNumber = getPhoneNumberFromAddress(String(cString: address))
            // For incomingcall
            if ( incomingPhoneNumber == "\(beacon.minor)"){
                // Need to create part get the phone number to set the minor value
                beaconProximityLabel.text = beaconProximity
                beaconRSSILabel.text = "\(beacon.rssi)"
            }
                
            // For outgoing call ( from UI )
            else if (phoneNumberTextField.text == "\(beacon.minor)" ){
                beaconProximityLabel.text = beaconProximity
                beaconRSSILabel.text = "\(beacon.rssi)"
            }
                
            // For outgoing call ( from MQTT Server )
            else if ( bedsidePhoneNumber == "\(beacon.minor)"){
                // Need to create part get the phone number to set the minor value
                beaconProximityLabel.text = beaconProximity
                beaconRSSILabel.text = "\(beacon.rssi)"
            }
            else {
                beaconProximityLabel.text = "Error"
                beaconRSSILabel.text = "Error"
            }
            
        }
    }
    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        print("Monitoring started")
    }
    private func locationManager(manager: CLLocationManager, monitoringDidFailForRegion region: CLRegion?, withError error: NSError) {
        print("Monitoring failed")
    }
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        if let beaconRegion = region as? CLBeaconRegion {
            print("DID ENTER REGION: uuid: \(beaconRegion.proximityUUID.uuidString)")
        }
    }
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        if let beaconRegion = region as? CLBeaconRegion {
            print("DID EXIT REGION: uuid: \(beaconRegion.proximityUUID.uuidString)")
        }
    }
}


