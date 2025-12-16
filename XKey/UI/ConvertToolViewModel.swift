//
//  ConvertToolViewModel.swift
//  XKey
//
//  ViewModel for convert tool
//

import Foundation
import AppKit

class ConvertToolViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var outputText: String = ""
    
    // Conversion options
    @Published var toAllCaps: Bool = false
    @Published var toAllNonCaps: Bool = false
    @Published var toCapsFirstLetter: Bool = false
    @Published var toCapsEachWord: Bool = false
    @Published var removeMark: Bool = false
    @Published var fromCode: Int = 0  // 0: Unicode, 1: TCVN3, 2: VNI
    @Published var toCode: Int = 0
    
    private let convertTool = ConvertTool()
    
    // MARK: - Actions
    
    func convert() {
        // Configure convert tool
        convertTool.toAllCaps = toAllCaps
        convertTool.toAllNonCaps = toAllNonCaps
        convertTool.toCapsFirstLetter = toCapsFirstLetter
        convertTool.toCapsEachWord = toCapsEachWord
        convertTool.removeMark = removeMark
        convertTool.fromCode = UInt8(fromCode)
        convertTool.toCode = UInt8(toCode)
        
        // Convert
        outputText = convertTool.convert(inputText)
    }
    
    func clear() {
        inputText = ""
        outputText = ""
        toAllCaps = false
        toAllNonCaps = false
        toCapsFirstLetter = false
        toCapsEachWord = false
        removeMark = false
        fromCode = 0
        toCode = 0
    }
    
    func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(outputText, forType: .string)
    }
}
