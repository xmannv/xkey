//
//  DonationView.swift
//  XKey
//
//  Donation dialog with QR codes for Momo and Bank
//

import SwiftUI

enum DonationMethod: String, CaseIterable {
    case momo = "Momo"
    case bank = "Bank"
}

struct DonationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMethod: DonationMethod = .momo
    @State private var isLoadingQR = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Support XKey")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Button(action: {
                        if let url = URL(string: "https://codetay.com") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        Text("A product of Codetay.com")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Tab selector
            Picker("", selection: $selectedMethod) {
                ForEach(DonationMethod.allCases, id: \.self) { method in
                    Text(method.rawValue).tag(method)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            // QR Code display
            ScrollView {
                VStack(spacing: 20) {
                    // QR Code image
                    QRCodeView(method: selectedMethod, isLoading: $isLoadingQR)
                        .frame(width: 300, height: 300)
                        .id(selectedMethod)
                    
                    // Instructions
                    Text(selectedMethod == .momo ? "Quét mã QR bằng ứng dụng Momo" : "Quét mã QR bằng ứng dụng ngân hàng")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    // Thank you message
                    Text("Mọi đóng góp của bạn đều giúp project bảo trì tốt hơn ❤️")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding()
            }
            

        }
        .frame(width: 450, height: 600)
    }
}

struct QRCodeView: View {
    let method: DonationMethod
    @Binding var isLoading: Bool
    
    var body: some View {
        ZStack {
            // Load QR code from bundled assets
            let imageName = method == .momo ? "qr_momo" : "qr_bank"
            
            if let nsImage = NSImage(named: imageName) {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    
                    Text("Không tìm thấy mã QR")
                        .font(.headline)
                    
                    Text("Vui lòng liên hệ developer")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
}

// MARK: - Preview

#Preview {
    DonationView()
}
