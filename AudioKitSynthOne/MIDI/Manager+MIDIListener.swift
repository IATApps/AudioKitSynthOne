//
//  Manager+MIDIListener.swift
//  AudioKitSynthOne
//
//  Created by AudioKit Contributors on 5/25/18.
//  Copyright © 2018 AudioKit. All rights reserved.
//

// AKMIDIListener protocol functions

extension Manager: AKMIDIListener {

    func setupNoteTrackerActions() {
        noteTracker.addAction(.on({ (noteNumber: MIDINoteNumber, velocity: MIDIVelocity) in
            self.keyboardView.pressAdded(noteNumber, velocity: velocity)
            //AKLog("keybboard:pressAdded: noteNumber: \(noteNumber), velocity:\(velocity) SYNC")
        }))

        noteTracker.addAction(.off({ (noteNumber: MIDINoteNumber, velocity: MIDIVelocity) in
            self.keyboardView.pressRemoved(noteNumber)
            //AKLog("keybboard:pressRemoved: noteNumber: \(noteNumber), velocity:\(velocity) SYNC")
            // KURT - this should be something that only the monophonic note tracker performs
            // Mono Mode
            // if in Mono Mode, then select the most recently pressed note and start it up
            if !self.keyboardView.polyphonicMode {
                guard let nextActiveNote = self.noteTracker.mostRecentNote else { return }
                self.keyboardView.pressAdded(nextActiveNote, velocity: velocity)
                //AKLog("keybboard:pressAdded: noteNumber: \(noteNumber), velocity:\(velocity) SYNC")
            }
        }))
    }

    public func receivedMIDINoteOn(noteNumber: MIDINoteNumber, velocity: MIDIVelocity, channel: MIDIChannel) {
        guard channel == midiChannelIn || omniMode else { return }
        var newVelocity = velocity
        if !appSettings.velocitySensitive { newVelocity = 127 }

        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.noteTracker.noteOn(channel: channel, noteNumber: noteNumber, velocity: newVelocity)
            }
        } else {
            self.noteTracker.noteOn(channel: channel, noteNumber: noteNumber, velocity: newVelocity)
        }
    }

    public func receivedMIDINoteOff(noteNumber: MIDINoteNumber, velocity: MIDIVelocity, channel: MIDIChannel) {
        guard (channel == midiChannelIn || omniMode) && !keyboardView.holdMode else { return }

        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.noteTracker.noteOff(channel: channel, noteNumber: noteNumber, velocity: velocity)
            }
        } else {
            self.noteTracker.noteOff(channel: channel, noteNumber: noteNumber, velocity: velocity)
        }
    }

    // Assign MIDI CC to active MIDI Learn knobs
    func assignMIDIControlToKnobs(cc: MIDIByte) {
        let activeMIDILearnKnobs = midiKnobs.filter { $0.isActive }
        for knob in  activeMIDILearnKnobs {
            knob.midiCC = cc
            knob.isActive = false
        }
    }

    // MIDI Controller input
    public func receivedMIDIController(_ controller: MIDIByte, value: MIDIByte, channel: MIDIChannel) {
        guard channel == midiChannelIn || omniMode else { return }
        AKLog("Channel: \(channel+1) controller: \(controller) value: \(value)")

        // KURT this should also involve a check if we are in MPE mode
        if self.keyboardView.polyphonicMode == false && channel != self.noteTracker.mostRecentChannel {
            return
        }

        // If any MIDI Learn knobs are active, assign the CC
        DispatchQueue.main.async {
            if self.midiLearnToggle.isSelected { self.assignMIDIControlToKnobs(cc: controller) }
        }

        // Handle MIDI Control Messages
        switch controller {

        // Mod Wheel
        case AKMIDIControl.modulationWheel.rawValue:
            DispatchQueue.main.async {
                self.modWheelPad.setVerticalValueFrom(midiValue: value)
            }

        // Sustain Pedal
        case AKMIDIControl.damperOnOff.rawValue:
            if value > 0 && !sustainMode {
                sustainer.sustain(down: true)
                sustainMode = true
            } else if sustainMode {
                sustainer.sustain(down: false)
                sustainMode = false
            }
            AKLog("value:\(value), sustainMode:\(sustainMode)")

        default:
            break
        }

        // Bank Change msb/cc0
        if controller == 0 {
            guard channel == midiChannelIn || omniMode else { return }

            if Int(value) != self.presetsViewController.bankIndex {
                AKLog ("DIFFERENT MSB")
                DispatchQueue.main.async {
                    self.presetsViewController.didSelectBank(index: Int(value))
                }
            }

        }

        // Check for MIDI learn knobs that match controller
        let matchingKnobs = midiKnobs.filter { $0.midiCC == controller }

        // Set new knob values from MIDI for matching knobs
        for midiKnob in matchingKnobs {
            DispatchQueue.main.async {
                midiKnob.setKnobValueFrom(midiValue: value)
            }
        }
    }

    // MIDI Program/Patch Change
    public func receivedMIDIProgramChange(_ program: MIDIByte, channel: MIDIChannel) {
        guard channel == midiChannelIn || omniMode else { return }
        guard !pcJustTriggered else { return }

        DispatchQueue.main.async {
            self.presetsViewController.didSelectPreset(index: Int(program))
        }

        // Prevent multiple triggers from multiple MIDI inputs
        pcJustTriggered = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.pcJustTriggered = false
        }
    }

    // MIDI Pitch Wheel
    public func receivedMIDIPitchWheel(_ pitchWheelValue: MIDIWord, channel: MIDIChannel) {
        guard channel == midiChannelIn || omniMode else { return }
        guard let s = Conductor.sharedInstance.synth else {
            AKLog("Can't process MIDI pitch wheel because synth is not instantiated")
            return
        }
        let val01 = Double(pitchWheelValue).normalized(from: 0...16_383)
        s.setDependentParameter(.pitchbend, val01, 0)
        // UI will be updated by dependentParameterDidChange()
    }

    // After touch
    public func receivedMIDIAfterTouch(_ pressure: MIDIByte, channel: MIDIChannel) {
        guard channel == midiChannelIn || omniMode else { return }
        // map to lfo targets
        //         self.conductor.tremolo.frequency = Double(pressure)/20.0
        // self.auMainController.tremoloKnob.setKnobValueFrom(midiValue: pressure)

        //verbose logging
        //AKLog("pressure: \(pressure), channel:\(channel)")
    }

    // MIDI Setup Change
    public func receivedMIDISetupChange() {
        AKLog("midi setup change, midi.inputNames: \(AudioKit.midi.inputNames)")

        let midiInputNames = AudioKit.midi.inputNames
        for inputName in midiInputNames {

            // check to see if input exists
            if let index = midiInputs.index(where: { $0.name == inputName }) {
                midiInputs.remove(at: index)
            }

            let newMIDI = MIDIInput(name: inputName, isOpen: true)
            midiInputs.append(newMIDI)
            AudioKit.midi.openInput(inputName)
        }
    }

    public func receivedMIDISystemCommand(_ data: [MIDIByte]) {
        // Suppress default logging - too verbose with clock messages
    }

}
