//
//  MQTTManager.swift
//  nurseUnit_Device
//
//  Created by Takdanai Jirawanichkul on 5/8/2562 BE.
//
import Foundation
import CocoaMQTT

struct theMQTT {
    static var manager: MQTTManager?
}

class MQTTManager : CocoaMQTTDelegate {
    static var isConnect: Bool = false
    let accountData = LocalUserData()
    var mqtt: CocoaMQTT?
    
    func startMQTT() {
        if MQTTManager.isConnect {
            print("MQTT already connect.")
        }
        else{
            print("Start MQTT Service")
            MQTTManager.isConnect = true
            mqttSetting()
            _ = mqtt?.connect()
        }
    }
    
    func stopMQTT(){
        print("Stop MQTT Service")
        MQTTManager.isConnect = false
        _ = mqtt?.disconnect()
    }
    
    func restartMQTTService(){
        stopMQTT()
        print("Restart MQTT Service")
        startMQTT()
    }
    
    // MARK : MQTT Publish message Function
    func acceptTask_PublishMessage(priorityTask : String ,taskID : String, bedID : String, nurseID : String){
        let string = priorityTask + "_risk_task_accept" + " " + taskID + " " + bedID
        mqtt?.publish("WEARABLE/" + nurseID , withString: string )
    }
    
    func rejectTask_PublishMessage(priorityTask : String ,taskID : String, bedID : String, nurseID : String){
        let string = priorityTask + "_risk_task_reject" + " " + taskID + " " + bedID
        mqtt?.publish("WEARABLE/" + nurseID , withString: string )
    }
    
    func finishTask_PublishMessage(priorityTask : String ,taskID : String, bedID : String, nurseID : String, patient_intention: String){
        let string = "task_complete" + " " + taskID + " " + bedID + " " + patient_intention
        mqtt?.publish("WEARABLE/" + nurseID, withString: string )
    }
    
    func login_PublishMessage(nurseID : String, deviceName : String){
        let string = "log_in" + " " + deviceName
        mqtt?.publish("WEARABLE/" + nurseID , withString: string )
    }
    
    func logout_PublishMessage(nurseID : String, deviceName : String){
        let string = "log_out" + " " + deviceName
        mqtt?.publish("WEARABLE/" + nurseID , withString: string )
    }
        
    
    // Send phone number  to OutgoingCallViewController
    // MARK: MQTT Setting
    func mqttSetting() {
        // Get MQTT Broker IP from PLIST File
        let brokerIP = accountData.getMQTTServerIp()!
        let clientID = "Bedside-" + String(ProcessInfo().processIdentifier)
        mqtt = CocoaMQTT(clientID: clientID, host: brokerIP, port: 1883)
        mqtt!.username = accountData.getMQTTUsername()
        mqtt!.password = accountData.getMQTTPassword()
        mqtt!.willMessage = CocoaMQTTWill(topic: "/will", message: "dieout")
        mqtt!.keepAlive = 60
        mqtt!.delegate = self
    }
    // MARK: MQTT Command
    // When Message Received
    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16 ) {
        TRACE("message: \(message.string.description), id: \(id)")
        // MQTT MESSAGE HANDLE PART
        let command = message.string!.components(separatedBy: " ")
        MainViewData.controller?.mqttMessageLabel.text = message.string?.description

        if command[0] == "low_risk_task_assign" {
            MainViewData.controller?.taskID = command[1]
            MainViewData.controller?.bedsidePhoneNumber = command[2]
            MainViewData.controller?.priorityTask = "low"
            MainViewData.controller?.taskAccept_Show()
            
            //mqtt.publish("wearable/104", withString: "Hello")
            // Assume Nurse answer
            // Publish message : task 'bedsitenumber' accept
            // And then make call
        }
        else if command[0] == "mid_risk_task_assign" {
            MainViewData.controller?.taskID = command[1]
            MainViewData.controller?.bedsidePhoneNumber = command[2]
            MainViewData.controller?.priorityTask = "mid"
            MainViewData.controller?.taskAccept_Show()
            // Assume Nurse answer
            // Publish message : task 'bedsitenumber' accept
            // And then make call
        }
        else if command[0] == "high_risk_task_assign" {
            MainViewData.controller?.taskID = command[1]
            MainViewData.controller?.bedsidePhoneNumber = command[2]
            MainViewData.controller?.priorityTask = "high"
            MainViewData.controller?.taskAccept_Show()
            // Assume Nurse answer
            // Publish message : task 'bedsitenumber' accept
            // And then make call
        }
        else if command[0] == "hide" {
            MainViewData.controller?.taskAccept_Hide()
            
        }
    }
    
    // When MQTT Server Connect
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        TRACE("ack: \(ack)")
        if ack == .accept {
            let mqttTopic = accountData.getMQTTTopic()! + "/" + accountData.getSipUsername()!
            // Set UI Label
            mqtt.subscribe(mqttTopic, qos: CocoaMQTTQOS.qos1)
            //mqtt.subscribe("Test", qos: CocoaMQTTQOS.qos1)
            MainViewData.controller?.mqttStatusLabel.text = "Connected to " + accountData.getMQTTServerIp()!
            MainViewData.controller?.mqttReconnectButton.isHidden = true
        }
    }
    
    // When MQTT Server Disconnect
    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        TRACE("\(err.debugDescription)")
        MainViewData.controller?.mqttStatusLabel.text = "Disconnect"
        // Try to disconnect every 5 seconds when MQTT server Disconnect
        //        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
        //            _ = mqtt.connect()
        //        }
    }
    
    // Another Function
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

