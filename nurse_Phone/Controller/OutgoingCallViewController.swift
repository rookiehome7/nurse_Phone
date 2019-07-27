//
//  OutgoingCallViewController.swift
//  bedsiteUnit_Phone
//
//  Created by Takdanai Jirawanichkul on 2/7/2562 BE.
//
import UIKit
import CoreLocation
import CoreBluetooth

struct OutgoingCallViewData{
    static var controller: OutgoingCallViewController?
    static var phoneNumber: String?
    static var statusLabel: UILabel?
    static var sipIcon: UIImageView?
    static var calleeName: String?
    static var callConnected: Bool?
    static var retry: Bool = false
}


struct OutgoingCallVT{
    static var lct: LinphoneCoreVTable = LinphoneCoreVTable()
}

var outgoingCallStateChanged: LinphoneCoreCallStateChangedCb = {
    (lc: Optional<OpaquePointer>, call: Optional<OpaquePointer>, callSate: LinphoneCallState,  message: Optional<UnsafePointer<Int8>>) in
    switch callSate{
    case LinphoneCallOutgoingProgress:
        NSLog("outgoingCallStateChanged: LinphoneCallReleased")
        if OutgoingCallViewData.retry == true{
            OutgoingCallViewData.retry = false
        }
    
    case LinphoneCallReleased:
        NSLog("outgoingCallStateChanged: LinphoneCallReleased")
        
    case LinphoneCallConnected:
        NSLog("outgoingCallStateChanged: LinphoneCallConnected")
        //OutgoingCallViewData.callType = CallLogType.outgoing_CALL_ANSWERED
        OutgoingCallViewData.controller?.statusLabel.text = "Connected"
        OutgoingCallViewData.callConnected = true

    case LinphoneCallError: /**<The call encountered an error, will not call LinphoneCallEnd*/
        NSLog("outgoingCallStateChanged: LinphoneCallError")
        OutgoingCallViewData.controller?.statusLabel.text = "Error"
        let message = String(cString: message!)
        NSLog(message)
        closeOutgoingCallView()
        
    case LinphoneCallEnd:
        NSLog("outgoingCallStateChanged: LinphoneCallEnd")
        OutgoingCallViewData.controller?.statusLabel.text = "EndCall"
        if OutgoingCallViewData.retry == false {
        closeOutgoingCallView()
        }
        
    default:
        NSLog("outgoingCallStateChanged: Default call state \(callSate)")
    }
}

func closeOutgoingCallView(){
    resetOutgoingCallData()
    OutgoingCallViewData.controller?.dismiss(animated: true, completion: nil)
}

func resetOutgoingCallData(){
    OutgoingCallViewData.callConnected = false
    OutgoingCallViewData.retry = false
}

class OutgoingCallViewController: UIViewController {
    
    var phoneNumber: String?
    var calleeName: String?
    
    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var sipImage: UIImageView!
    
    // User Data
    let accountData = LocalUserData() // Get function read file from PLIST
    // iBeacon Searching
    var locationManager: CLLocationManager!
    // iBeacon Broadcast
    var broadcastBeacon: CLBeaconRegion!
    var beaconPeripheralData: NSDictionary!
    var peripheralManager: CBPeripheralManager!
    

    override func viewDidLoad() {
        super.viewDidLoad()
        NSLog("OutgoingCallController.viewDidLoad()")
        
        // Get data from view controller
        resetOutgoingCallData()
        OutgoingCallViewData.controller = self
        OutgoingCallViewData.phoneNumber = phoneNumber
        OutgoingCallViewData.calleeName = phoneNumber // Try to set phone number
        OutgoingCallViewData.statusLabel = statusLabel
        
        // Set namelabel with phone number
        nameLabel.text = "Call: " + OutgoingCallViewData.calleeName!
        
        // iBeacon Searching Part
        locationManager = CLLocationManager()
        locationManager.delegate = self
        // Dont forgot to add in Info.plst file
        // Privacy - Location When In Use Usage Description & Location Always Usage Description
        locationManager.requestWhenInUseAuthorization()
        locationManager.requestAlwaysAuthorization()
        
        let lc = theLinphone.lc
        linphone_core_invite(lc, OutgoingCallViewData.phoneNumber)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        // Add CallStateChange listener
        OutgoingCallVT.lct.call_state_changed = outgoingCallStateChanged
        linphone_core_add_listener(theLinphone.lc!,  &OutgoingCallVT.lct)
        
        // Start Service : iBeacon Searching & Broadcast
        startSearchingBeacon()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        // Remove CallStateChange listener
        linphone_core_remove_listener(theLinphone.lc!, &OutgoingCallVT.lct)
        
        // Start Service : iBeacon Searching & Broadcast
        startSearchingBeacon()

        // Terminate Call First If it still have call
        terminateCall()
    }
    
    @IBAction func hangupButton(_ sender: Any) {
        terminateCall()
    }
    
    // TerminateCall and closed OutgingCallViewData
    func terminateCall(){
        let call = linphone_core_get_current_call(theLinphone.lc!)
        if call != nil {
            let result = linphone_core_terminate_call(theLinphone.lc!, call)
            NSLog("Terminated call result(outgoing): \(result)")
        }
        OutgoingCallViewData.controller?.dismiss(animated: false, completion: nil)
    }

}

// MARK: iBeacon - View Controller Extension Part
extension OutgoingCallViewController: CLLocationManagerDelegate {

    // MARK: iBeacon Searching Signal
    func startSearchingBeacon() {
        if let uuid = NSUUID(uuidString: accountData.getBeaconUUID()!) {
            print("Start Monitoring")
            let beaconRegion = CLBeaconRegion(proximityUUID: uuid as UUID, identifier: "iBeacon")
            startMonitoring(beaconRegion: beaconRegion)
            startRanging(beaconRegion: beaconRegion)
        }
    }
    func stopSearchingBeacon() {
        if let uuid = NSUUID(uuidString: accountData.getBeaconUUID()!) {
            print("Stop Monitoring")
            let beaconRegion = CLBeaconRegion(proximityUUID: uuid as UUID, identifier: "iBeacon")
            stopMonitoring(beaconRegion: beaconRegion)
            stopRanging(beaconRegion: beaconRegion)
        }
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
            print("BEACON RANGED: uuid: \(beacon.proximityUUID.uuidString) major: \(beacon.major)  minor: \(beacon.minor) proximity: \(beaconProximity)")
            //proximityLabel.text = beaconProximity
            
            // Example how to set the volume
            if (beaconProximity == "Immediate"){
                let vc = VolumeControl.sharedInstance
                vc.setVolume(volume: 0.1)
            }
            if (beaconProximity == "Near"){
                let vc = VolumeControl.sharedInstance
                vc.setVolume(volume: 0.50)
            }
            if (beaconProximity == "Far"){
                let vc = VolumeControl.sharedInstance
                vc.setVolume(volume: 1.0)
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

