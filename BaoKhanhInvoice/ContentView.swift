import SwiftUI
import UIKit

struct ContentView: View {
    @AppStorage("bk_api_base") private var apiBase: String = "https://manage.somet.vn/api/baokhanh"
    @AppStorage("bk_app_token") private var appToken: String = ""

    @State private var customerName: String = "Khách lẻ"
    @State private var discountText: String = ""
    @State private var items: [LocalInvoiceItem] = [LocalInvoiceItem(name: "", priceText: "")]

    @State private var currentInvoice: InvoiceInfo?
    @State private var qrText: String?
    @State private var statusMessage: String = ""
    @State private var isLoading: Bool = false
    @State private var showSettings: Bool = false
    @State private var pollTask: Task<Void, Never>?

    private var validItems: [LocalInvoiceItem] {
        items.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.price > 0 }
    }

    private var subtotal: Int {
        validItems.reduce(0) { $0 + $1.lineTotal }
    }

    private var discount: Int {
        min(Money.parse(discountText), subtotal)
    }

    private var payable: Int {
        max(0, subtotal - discount)
    }

    private var invoiceDateText: String {
        if let currentInvoice, let date = currentInvoice.invoice_date_vn, !date.isEmpty {
            return date
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    inputCard
                    actionButtons
                    invoiceCard
                    statusBox
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Bảo Khánh")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cài đặt") { showSettings = true }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(apiBase: $apiBase, appToken: $appToken)
            }
            .onDisappear {
                pollTask?.cancel()
                pollTask = nil
            }
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nhập đơn hàng")
                .font(.headline)

            TextField("Khách hàng", text: $customerName)
                .textFieldStyle(.roundedBorder)

            VStack(spacing: 10) {
                ForEach($items) { $item in
                    VStack(spacing: 8) {
                        HStack {
                            TextField("Tên sản phẩm", text: $item.name)
                                .textFieldStyle(.roundedBorder)
                            Button(role: .destructive) {
                                removeItem(item.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                            }
                        }
                        TextField("Giá tiền", text: $item.priceText)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            Button {
                items.append(LocalInvoiceItem(name: "", priceText: ""))
            } label: {
                Label("Thêm sản phẩm", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            TextField("Chiết khấu", text: $discountText)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)

            VStack(spacing: 6) {
                amountRow("Tổng tiền hàng", subtotal)
                amountRow("Chiết khấu", discount)
                Divider()
                amountRow("Thanh toán", payable, isBold: true)
            }
            .padding(10)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .cardStyle()
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                Task { await createInvoice() }
            } label: {
                HStack {
                    if isLoading { ProgressView().tint(.white) }
                    Text(isLoading ? "Đang tạo QR..." : "Tạo hóa đơn + QR")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)

            Button {
                newInvoice()
            } label: {
                Label("Tạo hóa đơn mới", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private var invoiceCard: some View {
        VStack(spacing: 12) {
            VStack(spacing: 3) {
                Text("BẢO KHÁNH")
                    .font(.title.bold())
                Text("131 Phú Mỹ - Mỹ Đình - Hà Nội")
                    .font(.footnote)
                Text("Điện thoại: 0368 248 972 - Zalo: 097 666 8193")
                    .font(.footnote)
            }
            .multilineTextAlignment(.center)

            Divider()

            Text("HÓA ĐƠN BÁN HÀNG")
                .font(.title3.bold())

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Số HĐ: \(currentInvoice?.invoice_code ?? "Chưa tạo")")
                    Text("Ngày: \(invoiceDateText)")
                    Text("Khách hàng: \(customerName.isEmpty ? "Khách lẻ" : customerName)")
                }
                .font(.subheadline)
                Spacer()
            }

            VStack(spacing: 0) {
                invoiceHeaderRow
                ForEach(validItems) { item in
                    invoiceItemRow(item)
                }
                if validItems.isEmpty {
                    Text("Nhập sản phẩm ở phía trên")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(.separator), lineWidth: 0.7)
            )

            VStack(spacing: 6) {
                amountRow("Tổng tiền hàng", subtotal)
                amountRow("Chiết khấu", discount)
                amountRow("Thanh toán", payable, isBold: true)
            }

            HStack(alignment: .bottom, spacing: 14) {
                VStack(spacing: 6) {
                    QRCodeImage(text: qrText, size: 138)
                    Text("QR thanh toán: \(Money.format(payable))")
                        .font(.caption.bold())
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 8) {
                    paymentStatusView
                    if let paidAt = currentInvoice?.paid_at_vn, !paidAt.isEmpty {
                        Text("Thời gian: \(paidAt)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Khách quét QR trên hóa đơn để thanh toán")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .cardStyle()
    }

    private var invoiceHeaderRow: some View {
        HStack(spacing: 0) {
            tableCell("Tên hàng", width: nil, bold: true, align: .leading)
            tableCell("SL", width: 34, bold: true, align: .center)
            tableCell("Đơn giá", width: 82, bold: true, align: .trailing)
            tableCell("Thành tiền", width: 92, bold: true, align: .trailing)
        }
        .background(Color(.secondarySystemGroupedBackground))
    }

    private func invoiceItemRow(_ item: LocalInvoiceItem) -> some View {
        HStack(spacing: 0) {
            tableCell(item.name.isEmpty ? "Sản phẩm" : item.name, width: nil, align: .leading)
            tableCell("1", width: 34, align: .center)
            tableCell(Money.format(item.price), width: 82, align: .trailing)
            tableCell(Money.format(item.lineTotal), width: 92, align: .trailing)
        }
    }

    private func tableCell(_ text: String, width: CGFloat?, bold: Bool = false, align: Alignment = .leading) -> some View {
        Text(text)
            .font(bold ? .caption.bold() : .caption)
            .lineLimit(2)
            .minimumScaleFactor(0.75)
            .frame(width: width, alignment: align)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: align)
            .padding(.horizontal, 5)
            .padding(.vertical, 8)
            .border(Color(.separator), width: 0.35)
    }

    private func amountRow(_ title: String, _ amount: Int, isBold: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(Money.format(amount))
        }
        .font(isBold ? .headline : .subheadline)
    }

    private var paymentStatusView: some View {
        let status = (currentInvoice?.payment_status ?? "").uppercased()
        return Text(status == "PAID" ? "✅ Đã thanh toán" : (status == "PENDING" ? "Chưa thanh toán" : "Chưa tạo hóa đơn"))
            .font(.headline)
            .foregroundStyle(status == "PAID" ? Color.green : Color.orange)
    }

    private var statusBox: some View {
        Group {
            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func removeItem(_ id: UUID) {
        if items.count <= 1 {
            items[0] = LocalInvoiceItem(name: "", priceText: "")
        } else {
            items.removeAll { $0.id == id }
        }
    }

    @MainActor
    private func createInvoice() async {
        let rows = validItems.filter { $0.price > 0 }
        guard !rows.isEmpty else {
            statusMessage = "Bạn cần nhập ít nhất 1 sản phẩm có giá tiền."
            return
        }
        guard payable > 0 else {
            statusMessage = "Tổng thanh toán phải lớn hơn 0."
            return
        }

        isLoading = true
        statusMessage = "Đang gửi hóa đơn lên manage.somet.vn để tạo QR payOS..."
        pollTask?.cancel()
        pollTask = nil

        let request = CreateInvoiceRequest(
            customer_name: customerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Khách lẻ" : customerName,
            discount: discount,
            items: rows.map { CreateInvoiceItem(name: $0.name.isEmpty ? "Sản phẩm" : $0.name, quantity: 1, price: $0.price) }
        )

        do {
            let response = try await APIClient.createInvoice(apiBase: apiBase, token: appToken, request: request)
            currentInvoice = response.invoice
            qrText = response.payment.qrCode
            statusMessage = "Đã tạo hóa đơn và QR. Khách quét QR ngay trên hóa đơn để thanh toán."
            startPolling(orderCode: response.invoice.order_code)
        } catch {
            statusMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func startPolling(orderCode: String) {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await checkStatus(orderCode: orderCode)
            }
        }
    }

    @MainActor
    private func checkStatus(orderCode: String) async {
        do {
            let response = try await APIClient.checkStatus(apiBase: apiBase, token: appToken, orderCode: orderCode)
            currentInvoice = response.invoice
            if response.invoice.payment_status.uppercased() == "PAID" {
                statusMessage = "Khách đã thanh toán thành công."
                pollTask?.cancel()
                pollTask = nil
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } catch {
            // Không hiện lỗi liên tục khi đang polling.
        }
    }

    private func newInvoice() {
        pollTask?.cancel()
        pollTask = nil
        customerName = "Khách lẻ"
        discountText = ""
        items = [LocalInvoiceItem(name: "", priceText: "")]
        currentInvoice = nil
        qrText = nil
        statusMessage = ""
    }
}

private struct SettingsView: View {
    @Binding var apiBase: String
    @Binding var appToken: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("API manage.somet.vn") {
                    TextField("API Base", text: $apiBase)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    SecureField("Token API nếu có", text: $appToken)
                    Text("Mặc định: https://manage.somet.vn/api/baokhanh")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Ghi chú") {
                    Text("Nếu /api/baokhanh/config.php để app_token rỗng thì Token trong app cũng để trống.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Cài đặt")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Xong") { dismiss() }
                }
            }
        }
    }
}

private extension View {
    func cardStyle() -> some View {
        self
            .padding(14)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
    }
}
