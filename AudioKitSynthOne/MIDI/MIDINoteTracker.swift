//
//  MIDINoteTrackerProtocol.swift
//  AudioKitSynthOne
//
//  Created by Kurt Arnlund on 2/21/19.
//  Copyright © 2019 AudioKit. All rights reserved.
//

import Foundation

class MIDINoteTracker {
    public typealias NoteActionClosure = (_ noteNumber: MIDINoteNumber, _ velocity: MIDIVelocity) -> ()

    enum NoteAction {
        case on(NoteActionClosure)
        case off(NoteActionClosure)
        case velocityChange(NoteActionClosure)

        var isOn: Bool {
            switch self {
            case .on(_):
                return true
            default:
                return false
            }
        }

        var isOff: Bool {
            switch self {
            case .off(_):
                return true
            default:
                return false
            }
        }

        var isVelocityChange: Bool {
            switch self {
            case .velocityChange(_):
                return true
            default:
                return false
            }
        }

        func callAction(noteNumber: MIDINoteNumber, velocity: MIDIVelocity = 127) {
            switch self {
            case .on(let action):
                action(noteNumber, velocity)
            case .off(let action):
                action(noteNumber, velocity)
            case .velocityChange(let action):
                action(noteNumber, velocity)
            }
        }
    }

    /// This should be an array of 128 entries.
    /// Each note number indexes into this array.
    /// Each array entry is the order in which that note was pressed, or 0 for not pressed.
    var activeNotes: [Int] = Array(repeating: 0, count: 128)
    var activeVelocity: [MIDIVelocity] = Array(repeating: 0, count: 128)
    var activeChannel: [MIDIChannel] = Array(repeating: 0, count: 128)
    var activeNoteIndex: Int = 0
    var actions: [NoteAction] = []

    func addAction(_ action: NoteAction) {
        actions.append(action)
    }

    func removeAllActions() {
        actions = []
    }

    func callOnActions(noteNumber: MIDINoteNumber, velocity: MIDIVelocity = 127) {
        let actions = self.actions.filter { $0.isOn }
        for action in actions {
            action.callAction(noteNumber: noteNumber, velocity: velocity)
        }
    }

    func callOffActions(noteNumber: MIDINoteNumber, velocity: MIDIVelocity = 127) {
        let actions = self.actions.filter { $0.isOff }
        for action in actions {
            action.callAction(noteNumber: noteNumber, velocity: velocity)
        }
    }

    func callVelChangeActions(noteNumber: MIDINoteNumber, velocity: MIDIVelocity = 127) {
        let actions = self.actions.filter { $0.isVelocityChange }
        for action in actions {
            action.callAction(noteNumber: noteNumber, velocity: velocity)
        }
    }

    var mostRecentNote: MIDINoteNumber? {
        guard activeNoteIndex > 0 else { return nil }
        guard let maxIndex = activeNotes.max() else { return nil }
        guard maxIndex > 0 else { return nil }
        let note = activeNotes.index(of:maxIndex)!
        return UInt8(note)
    }

    var mostRecentChannel: MIDIChannel? {
        guard let recentNote = mostRecentNote else { return nil }
        return UInt8(activeChannel[Int(recentNote)])
    }

    func noteOn(channel: MIDIChannel, noteNumber: MIDINoteNumber, velocity: MIDIVelocity = 127) {
        let noteIndex = Int(noteNumber)
        // protect against double note on
        guard self.activeNotes[noteIndex] == 0 else {
            self.activeVelocity[noteIndex] = velocity
            callVelChangeActions(noteNumber: noteNumber, velocity: velocity)
            AKLog("velChange - noteNumber: \(noteNumber), velocity:\(velocity), active note index: \(self.activeNoteIndex)")
            return
        }

        self.activeNoteIndex += 1
        self.activeNotes[noteIndex] = self.activeNoteIndex
        self.activeVelocity[noteIndex] = velocity
        self.activeChannel[noteIndex] = channel
        callOnActions(noteNumber: noteNumber, velocity: velocity)
        AKLog("noteNumber: \(noteNumber), velocity:\(velocity), active note index: \(self.activeNoteIndex)")
    }

    func noteOff(channel: MIDIChannel, noteNumber: MIDINoteNumber, velocity: MIDIVelocity = 127) {
        let noteIndex = Int(noteNumber)
        // protect against double note off
        guard self.activeNotes[noteIndex] > 0 else {
            self.activeVelocity[noteIndex] = velocity
            callVelChangeActions(noteNumber: noteNumber, velocity: velocity)
            AKLog("velChange - noteNumber: \(noteNumber), velocity:\(velocity), active note index: \(self.activeNoteIndex)")
            return
        }

        self.activeNotes[noteIndex] = 0
        self.activeVelocity[noteIndex] = velocity
        self.activeChannel[noteIndex] = 0
        self.activeNoteIndex -= 1
        callOffActions(noteNumber: noteNumber, velocity: velocity)
        AKLog("noteNumber: \(noteNumber), velocity:\(velocity), active note index: \(self.activeNoteIndex)")
    }
}
