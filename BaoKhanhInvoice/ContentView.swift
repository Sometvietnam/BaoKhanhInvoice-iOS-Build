import SwiftUI
import UIKit

struct ContentView: View {
    @AppStorage("bk_api_base") private var apiBase: String = "https://manage.somet.vn/api/baokhanh"
    @AppStorage("bk_app_token") private var appToken: String = ""
    @AppStorage("bk_saved_invoices_json") private var savedInvoicesJSON: String = "[]"

    @State private var customerName: String = "Khách lẻ"
    @State private var discountText: String = ""
    @State private var items: [LocalInvoiceItem] = [LocalInvoiceItem(name: "", priceText: "")]

    @State private var currentInvoice: InvoiceInfo?
    @State private var qrText: String?
    @State private var statusMessage: String = ""
    @State private var isLoading: Bool = false
    @State private var pollTask: Task<Void, Never>?
    @State private var savedInvoices: [SavedInvoiceRecord] = []
    @FocusState private var inputFocused: Bool

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
                    savedInvoicesCard
                    statusBox
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground).onTapGesture { hideKeyboard() })
            .navigationTitle("Bảo Khánh")
            .onAppear {
                loadSavedInvoices()
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
                .focused($inputFocused)

            VStack(spacing: 10) {
                ForEach($items) { $item in
                    VStack(spacing: 8) {
                        HStack {
                            TextField("Tên sản phẩm", text: $item.name)
                                .textFieldStyle(.roundedBorder)
                                .focused($inputFocused)
                            Button(role: .destructive) {
                                removeItem(item.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                            }
                        }
                        HStack(spacing: 8) {
                            TextField("SL", text: Binding(
                                get: { String(max(1, $item.wrappedValue.quantity)) },
                                set: { newValue in
                                    let digits = newValue.filter { $0.isNumber }
                                    $item.wrappedValue.quantity = max(1, Int(digits) ?? 1)
                                }
                            ))
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .focused($inputFocused)
                            .frame(width: 76)

                            TextField("Giá tiền", text: $item.priceText)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                                .focused($inputFocused)
                        }
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
                .focused($inputFocused)

            VStack(spacing: 6) {
                AmountLine(title: "Tổng tiền hàng", amount: subtotal)
                AmountLine(title: "Chiết khấu", amount: discount)
                Divider()
                AmountLine(title: "Thanh toán", amount: payable, isBold: true)
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
                hideKeyboard()
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

            HStack(spacing: 10) {
                Button {
                    saveCurrentInvoiceManually()
                } label: {
                    Label("Lưu hóa đơn", systemImage: "tray.and.arrow.down.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(currentInvoice == nil)

                Button {
                    saveInvoiceImageToPhotos()
                } label: {
                    Label("Tải ảnh hóa đơn", systemImage: "photo.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(currentInvoice == nil)
            }

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
        InvoiceCardView(
            customerName: customerName.isEmpty ? "Khách lẻ" : customerName,
            items: validItems,
            currentInvoice: currentInvoice,
            qrText: qrText,
            invoiceDateText: invoiceDateText,
            subtotal: subtotal,
            discount: discount,
            payable: payable
        )
        .cardStyle()
        .contentShape(Rectangle())
        .onTapGesture { hideKeyboard() }
    }

    private var savedInvoicesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Hóa đơn đã lưu")
                    .font(.headline)
                Spacer()
                if !savedInvoices.isEmpty {
                    Text("\(savedInvoices.count)")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(Capsule())
                }
            }

            if savedInvoices.isEmpty {
                Text("Sau khi tạo hóa đơn + QR, app sẽ tự lưu hóa đơn tại đây.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(savedInvoices.prefix(15)) { record in
                    Button {
                        loadSavedInvoice(record)
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(record.invoice_code)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)
                                Text(record.customer_name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(record.invoice_date_vn ?? record.saved_at)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(Money.format(record.total_amount))
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)
                                Text(record.payment_status.uppercased() == "PAID" ? "Đã thanh toán" : "Chưa thanh toán")
                                    .font(.caption.bold())
                                    .foregroundStyle(record.payment_status.uppercased() == "PAID" ? .green : .orange)
                            }
                        }
                        .padding(10)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            deleteSavedInvoice(record)
                        } label: {
                            Label("Xóa hóa đơn này", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .cardStyle()
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
            items: rows.map { CreateInvoiceItem(name: $0.name.isEmpty ? "Sản phẩm" : $0.name, quantity: max(1, $0.quantity), price: $0.price) }
        )

        do {
            let response = try await APIClient.createInvoice(apiBase: apiBase, token: appToken, request: request)
            currentInvoice = response.invoice
            qrText = response.payment.qrCode
            persistCurrentInvoice(showMessage: false)
            statusMessage = "Đã tạo hóa đơn, đã lưu vào app và đã có QR. Khách quét QR ngay trên hóa đơn để thanh toán."
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
            updateSavedInvoiceStatus(response.invoice)
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
        hideKeyboard()
        pollTask?.cancel()
        pollTask = nil
        customerName = "Khách lẻ"
        discountText = ""
        items = [LocalInvoiceItem(name: "", priceText: "")]
        currentInvoice = nil
        qrText = nil
        statusMessage = ""
    }

    private func hideKeyboard() {
        inputFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func loadSavedInvoices() {
        guard let data = savedInvoicesJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([SavedInvoiceRecord].self, from: data) else {
            savedInvoices = []
            return
        }
        savedInvoices = decoded
    }

    private func writeSavedInvoices() {
        let limited = Array(savedInvoices.prefix(100))
        savedInvoices = limited
        if let data = try? JSONEncoder().encode(limited),
           let json = String(data: data, encoding: .utf8) {
            savedInvoicesJSON = json
        }
    }

    private func makeCurrentSavedRecord() -> SavedInvoiceRecord? {
        guard let invoice = currentInvoice else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "dd/MM/yyyy HH:mm"
        return SavedInvoiceRecord(
            invoice_code: invoice.invoice_code,
            order_code: invoice.order_code,
            invoice_date_vn: invoice.invoice_date_vn ?? invoiceDateText,
            customer_name: customerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Khách lẻ" : customerName,
            items: validItems.map { SavedInvoiceItem(name: $0.name.isEmpty ? "Sản phẩm" : $0.name, quantity: max(1, $0.quantity), price: $0.price) },
            subtotal: subtotal,
            discount: discount,
            total_amount: payable,
            payment_status: invoice.payment_status,
            status_text: invoice.status_text,
            paid_at_vn: invoice.paid_at_vn,
            qr_text: qrText,
            saved_at: formatter.string(from: Date())
        )
    }

    private func persistCurrentInvoice(showMessage: Bool) {
        guard let record = makeCurrentSavedRecord() else {
            if showMessage { statusMessage = "Bạn cần tạo hóa đơn trước khi lưu." }
            return
        }
        savedInvoices.removeAll { $0.invoice_code == record.invoice_code || $0.order_code == record.order_code }
        savedInvoices.insert(record, at: 0)
        writeSavedInvoices()
        if showMessage { statusMessage = "Đã lưu hóa đơn \(record.invoice_code) trong app." }
    }

    private func saveCurrentInvoiceManually() {
        hideKeyboard()
        persistCurrentInvoice(showMessage: true)
    }

    private func updateSavedInvoiceStatus(_ invoice: InvoiceInfo) {
        guard let index = savedInvoices.firstIndex(where: { $0.order_code == invoice.order_code || $0.invoice_code == invoice.invoice_code }) else { return }
        savedInvoices[index].payment_status = invoice.payment_status
        savedInvoices[index].status_text = invoice.status_text
        savedInvoices[index].paid_at_vn = invoice.paid_at_vn
        writeSavedInvoices()
    }

    private func loadSavedInvoice(_ record: SavedInvoiceRecord) {
        hideKeyboard()
        customerName = record.customer_name
        discountText = record.discount > 0 ? String(record.discount) : ""
        items = record.toLocalItems()
        currentInvoice = record.toInvoiceInfo()
        qrText = record.qr_text
        statusMessage = "Đã mở lại hóa đơn \(record.invoice_code)."
        if record.payment_status.uppercased() != "PAID" {
            startPolling(orderCode: record.order_code)
        } else {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    private func deleteSavedInvoice(_ record: SavedInvoiceRecord) {
        savedInvoices.removeAll { $0.invoice_code == record.invoice_code }
        writeSavedInvoices()
        statusMessage = "Đã xóa hóa đơn \(record.invoice_code) khỏi danh sách lưu trong app."
    }

    @MainActor
    private func saveInvoiceImageToPhotos() {
        hideKeyboard()
        guard currentInvoice != nil else {
            statusMessage = "Bạn cần tạo hóa đơn + QR trước khi tải ảnh."
            return
        }

        let printable = InvoiceCardView(
            customerName: customerName.isEmpty ? "Khách lẻ" : customerName,
            items: validItems,
            currentInvoice: currentInvoice,
            qrText: qrText,
            invoiceDateText: invoiceDateText,
            subtotal: subtotal,
            discount: discount,
            payable: payable
        )
        .padding(18)
        .frame(width: 390)
        .background(Color.white)

        let renderer = ImageRenderer(content: printable)
        renderer.scale = UIScreen.main.scale

        guard let image = renderer.uiImage else {
            statusMessage = "Không tạo được ảnh hóa đơn."
            return
        }

        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        statusMessage = "Đã lưu ảnh hóa đơn vào Ảnh trên iPhone."
    }
}

private struct InvoiceCardView: View {
    let customerName: String
    let items: [LocalInvoiceItem]
    let currentInvoice: InvoiceInfo?
    let qrText: String?
    let invoiceDateText: String
    let subtotal: Int
    let discount: Int
    let payable: Int

    var body: some View {
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
                InvoiceHeaderRow()
                ForEach(items) { item in
                    InvoiceItemRow(item: item)
                }
                if items.isEmpty {
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
                AmountLine(title: "Tổng tiền hàng", amount: subtotal)
                AmountLine(title: "Chiết khấu", amount: discount)
                AmountLine(title: "Thanh toán", amount: payable, isBold: true)
            }

            HStack(alignment: .bottom, spacing: 14) {
                VStack(spacing: 6) {
                    QRCodeImage(text: qrText, size: 138)
                    Text("QR thanh toán: \(Money.format(payable))")
                        .font(.caption.bold())
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 8) {
                    PaymentStatusView(invoice: currentInvoice)
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
    }
}

private struct PaymentStatusView: View {
    let invoice: InvoiceInfo?

    var body: some View {
        let status = (invoice?.payment_status ?? "").uppercased()
        Text(status == "PAID" ? "✅ Đã thanh toán" : (status == "PENDING" ? "Chưa thanh toán" : "Chưa tạo hóa đơn"))
            .font(.headline)
            .foregroundStyle(status == "PAID" ? Color.green : Color.orange)
    }
}

private struct AmountLine: View {
    let title: String
    let amount: Int
    var isBold: Bool = false

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(Money.format(amount))
        }
        .font(isBold ? .headline : .subheadline)
    }
}

private struct InvoiceHeaderRow: View {
    var body: some View {
        HStack(spacing: 0) {
            TableCell(text: "Tên hàng", width: nil, bold: true, align: .leading)
            TableCell(text: "SL", width: 34, bold: true, align: .center)
            TableCell(text: "Đơn giá", width: 82, bold: true, align: .trailing)
            TableCell(text: "Thành tiền", width: 92, bold: true, align: .trailing)
        }
        .background(Color(.secondarySystemGroupedBackground))
    }
}

private struct InvoiceItemRow: View {
    let item: LocalInvoiceItem

    var body: some View {
        HStack(spacing: 0) {
            TableCell(text: item.name.isEmpty ? "Sản phẩm" : item.name, width: nil, align: .leading)
            TableCell(text: String(max(1, item.quantity)), width: 34, align: .center)
            TableCell(text: Money.format(item.price), width: 82, align: .trailing)
            TableCell(text: Money.format(item.lineTotal), width: 92, align: .trailing)
        }
    }
}

private struct TableCell: View {
    let text: String
    let width: CGFloat?
    var bold: Bool = false
    var align: Alignment = .leading

    var body: some View {
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
