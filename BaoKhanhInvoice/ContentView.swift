import SwiftUI
import UIKit

struct ContentView: View {
    @AppStorage("bk_api_base") private var apiBase: String = "https://manage.somet.vn/api/baokhanh"
    @AppStorage("bk_app_token") private var appToken: String = ""
    @AppStorage("bk_saved_invoices_json") private var savedInvoicesJSON: String = "[]"

    @State private var selectedTab: Int = 0
    @State private var customerName: String = "Khách lẻ"
    @State private var discountText: String = ""
    @State private var items: [LocalInvoiceItem] = [LocalInvoiceItem(name: "", priceText: "")]

    @State private var currentInvoice: InvoiceInfo?
    @State private var editingInvoiceCode: String?
    @State private var qrText: String?
    @State private var statusMessage: String = ""
    @State private var isLoading: Bool = false
    @State private var isRefreshingStatus: Bool = false
    @State private var pollTask: Task<Void, Never>?
    @State private var savedInvoices: [SavedInvoiceRecord] = []
    @State private var historyDate: Date = Date()
    @State private var revenueDate: Date = Date()
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
        return Self.dayFormatter.string(from: Date())
    }

    private var historyInvoices: [SavedInvoiceRecord] {
        savedInvoices
            .filter { record in
                guard let date = dateForInvoice(record) else { return false }
                return Calendar.current.isDate(date, inSameDayAs: historyDate)
            }
            .sorted { (dateForInvoice($0) ?? .distantPast) > (dateForInvoice($1) ?? .distantPast) }
    }

    private var paidHistoryCount: Int {
        historyInvoices.filter { $0.isPaid }.count
    }

    private var unpaidHistoryCount: Int {
        historyInvoices.filter { !$0.isPaid }.count
    }

    private var paidInvoices: [SavedInvoiceRecord] {
        savedInvoices.filter { $0.isPaid }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            createInvoiceTab
                .tabItem { Label("Tạo hóa đơn", systemImage: "doc.badge.plus") }
                .tag(0)

            historyTab
                .tabItem { Label("Lịch sử", systemImage: "clock.arrow.circlepath") }
                .tag(1)

            revenueTab
                .tabItem { Label("Doanh thu", systemImage: "chart.bar.xaxis") }
                .tag(2)
        }
        .onAppear {
            loadSavedInvoices()
            Task { await refreshPendingInvoices() }
        }
        .onChange(of: selectedTab) { _ in
            hideKeyboard()
            loadSavedInvoices()
            if selectedTab != 0 {
                Task { await refreshPendingInvoices() }
            }
        }
        .onDisappear {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    private var createInvoiceTab: some View {
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
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground).onTapGesture { hideKeyboard() })
            .navigationTitle("Bảo Khánh")
        }
    }

    private var historyTab: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 12) {
                        DatePicker("Chọn ngày", selection: $historyDate, displayedComponents: .date)
                            .datePickerStyle(.compact)

                        HStack(spacing: 10) {
                            MiniStatBox(title: "Đã thanh toán", value: "\(paidHistoryCount)", color: .green)
                            MiniStatBox(title: "Chưa thanh toán", value: "\(unpaidHistoryCount)", color: .red)
                        }

                        Button {
                            Task { await refreshPendingInvoices() }
                        } label: {
                            HStack {
                                if isRefreshingStatus { ProgressView() }
                                Label("Cập nhật trạng thái", systemImage: "arrow.clockwise")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRefreshingStatus)
                    }
                    .cardStyle()

                    if historyInvoices.isEmpty {
                        Text("Không có hóa đơn trong ngày đã chọn.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    } else {
                        VStack(spacing: 10) {
                            ForEach(historyInvoices) { record in
                                HistoryInvoiceRow(record: record) {
                                    openInvoiceFromHistory(record)
                                } onEdit: {
                                    openInvoiceFromHistory(record)
                                } onDelete: {
                                    Task { await deleteInvoice(record) }
                                }
                            }
                        }
                    }

                    statusBox
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Lịch sử hóa đơn")
        }
    }

    private var revenueTab: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    RevenueSummaryCard(
                        today: revenueForDay(Date()),
                        month: revenueForMonth(Date()),
                        year: revenueForYear(Date())
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Xem lại doanh thu theo ngày")
                            .font(.headline)

                        DatePicker("Chọn ngày", selection: $revenueDate, displayedComponents: .date)
                            .datePickerStyle(.compact)

                        RevenueLine(title: "Doanh thu ngày đã chọn", amount: revenueForDay(revenueDate), color: .blue)
                        Text(Self.dayFormatter.string(from: revenueDate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .cardStyle()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Ghi chú")
                            .font(.headline)
                        Text("Doanh thu chỉ tính các hóa đơn đã thanh toán màu xanh. Hóa đơn chưa thanh toán màu đỏ chưa được cộng vào doanh thu.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .cardStyle()
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Doanh thu")
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(editingInvoiceCode == nil ? "Nhập đơn hàng" : "Sửa hóa đơn")
                    .font(.headline)
                Spacer()
                if let editingInvoiceCode {
                    Text(editingInvoiceCode)
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

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
                Task {
                    if editingInvoiceCode == nil {
                        await createInvoice()
                    } else {
                        await updateCurrentInvoice()
                    }
                }
            } label: {
                HStack {
                    if isLoading { ProgressView().tint(.white) }
                    Text(primaryButtonText)
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

    private var primaryButtonText: String {
        if isLoading {
            return editingInvoiceCode == nil ? "Đang tạo QR..." : "Đang cập nhật QR..."
        }
        return editingInvoiceCode == nil ? "Tạo hóa đơn + QR" : "Cập nhật hóa đơn + QR"
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
        guard validateRows(rows) else { return }

        isLoading = true
        statusMessage = "Đang gửi hóa đơn lên manage.somet.vn để tạo QR payOS..."
        pollTask?.cancel()
        pollTask = nil

        let request = CreateInvoiceRequest(
            customer_name: normalizedCustomerName,
            discount: discount,
            items: rows.map { CreateInvoiceItem(name: $0.name.isEmpty ? "Sản phẩm" : $0.name, quantity: max(1, $0.quantity), price: $0.price) }
        )

        do {
            let response = try await APIClient.createInvoice(apiBase: apiBase, token: appToken, request: request)
            editingInvoiceCode = nil
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

    @MainActor
    private func updateCurrentInvoice() async {
        let rows = validItems.filter { $0.price > 0 }
        guard validateRows(rows) else { return }
        guard let invoice = currentInvoice else {
            statusMessage = "Bạn cần mở hóa đơn từ tab Lịch sử trước khi sửa."
            return
        }

        isLoading = true
        statusMessage = "Đang cập nhật hóa đơn cũ và tạo lại QR theo số tiền mới..."
        pollTask?.cancel()
        pollTask = nil

        let request = UpdateInvoiceRequest(
            invoice_code: invoice.invoice_code,
            order_code: invoice.order_code,
            customer_name: normalizedCustomerName,
            discount: discount,
            items: rows.map { CreateInvoiceItem(name: $0.name.isEmpty ? "Sản phẩm" : $0.name, quantity: max(1, $0.quantity), price: $0.price) }
        )

        do {
            let response = try await APIClient.updateInvoice(apiBase: apiBase, token: appToken, request: request)
            editingInvoiceCode = response.invoice.invoice_code
            currentInvoice = response.invoice
            qrText = response.payment.qrCode
            persistCurrentInvoice(showMessage: false)
            statusMessage = "Đã cập nhật chính hóa đơn \(response.invoice.invoice_code). Trạng thái đã chuyển về CHƯA THANH TOÁN màu đỏ và QR đã đổi theo số tiền mới."
            startPolling(orderCode: response.invoice.order_code)
        } catch {
            statusMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func validateRows(_ rows: [LocalInvoiceItem]) -> Bool {
        guard !rows.isEmpty else {
            statusMessage = "Bạn cần nhập ít nhất 1 sản phẩm có giá tiền."
            return false
        }
        guard payable > 0 else {
            statusMessage = "Tổng thanh toán phải lớn hơn 0."
            return false
        }
        return true
    }

    private var normalizedCustomerName: String {
        customerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Khách lẻ" : customerName.trimmingCharacters(in: .whitespacesAndNewlines)
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
            mergeCurrentInvoiceStatus(response.invoice)
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

    @MainActor
    private func refreshPendingInvoices() async {
        if isRefreshingStatus { return }
        isRefreshingStatus = true
        let pending = savedInvoices.filter { !$0.isPaid }
        for record in pending {
            do {
                let response = try await APIClient.checkStatus(apiBase: apiBase, token: appToken, orderCode: record.order_code)
                updateSavedInvoiceStatus(response.invoice)
                mergeCurrentInvoiceStatus(response.invoice)
            } catch {
                // Bỏ qua từng hóa đơn lỗi để các hóa đơn khác vẫn được kiểm tra.
            }
        }
        isRefreshingStatus = false
    }

    private func newInvoice() {
        hideKeyboard()
        pollTask?.cancel()
        editingInvoiceCode = nil
        customerName = "Khách lẻ"
        discountText = ""
        items = [LocalInvoiceItem(name: "", priceText: "")]
        currentInvoice = nil
        qrText = nil
        statusMessage = "Đã sẵn sàng tạo hóa đơn mới."
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
        let limited = Array(savedInvoices.prefix(500))
        savedInvoices = limited
        if let data = try? JSONEncoder().encode(limited),
           let json = String(data: data, encoding: .utf8) {
            savedInvoicesJSON = json
        }
    }

    private func makeCurrentSavedRecord() -> SavedInvoiceRecord? {
        guard let invoice = currentInvoice else { return nil }
        return SavedInvoiceRecord(
            invoice_code: invoice.invoice_code,
            order_code: invoice.order_code,
            invoice_date_vn: invoice.invoice_date_vn ?? invoiceDateText,
            customer_name: normalizedCustomerName,
            items: validItems.map { SavedInvoiceItem(name: $0.name.isEmpty ? "Sản phẩm" : $0.name, quantity: max(1, $0.quantity), price: $0.price) },
            subtotal: subtotal,
            discount: discount,
            total_amount: payable,
            payment_status: invoice.payment_status,
            status_text: invoice.status_text,
            paid_at_vn: invoice.paid_at_vn,
            qr_text: qrText,
            saved_at: Self.fullFormatter.string(from: Date())
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

    private func mergeCurrentInvoiceStatus(_ invoice: InvoiceInfo) {
        guard let current = currentInvoice,
              current.order_code == invoice.order_code || current.invoice_code == invoice.invoice_code else { return }
        currentInvoice = InvoiceInfo(
            id: current.id,
            invoice_code: current.invoice_code,
            order_code: current.order_code,
            invoice_date_vn: current.invoice_date_vn,
            subtotal: current.subtotal,
            discount: current.discount,
            total_amount: current.total_amount,
            payment_status: invoice.payment_status,
            status_text: invoice.status_text,
            paid_at: invoice.paid_at,
            paid_at_vn: invoice.paid_at_vn
        )
    }

    private func openInvoiceFromHistory(_ record: SavedInvoiceRecord) {
        hideKeyboard()
        customerName = record.customer_name
        discountText = record.discount > 0 ? String(record.discount) : ""
        items = record.toLocalItems()
        currentInvoice = record.toInvoiceInfo()
        editingInvoiceCode = record.invoice_code
        qrText = record.qr_text
        statusMessage = "Đã mở hóa đơn \(record.invoice_code). Sửa xong bấm Cập nhật hóa đơn + QR để cập nhật chính hóa đơn này."
        selectedTab = 0
        if record.payment_status.uppercased() != "PAID" {
            startPolling(orderCode: record.order_code)
        } else {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    @MainActor
    private func deleteInvoice(_ record: SavedInvoiceRecord) async {
        hideKeyboard()
        savedInvoices.removeAll { $0.invoice_code == record.invoice_code }
        writeSavedInvoices()
        if currentInvoice?.invoice_code == record.invoice_code {
            newInvoice()
        }
        statusMessage = "Đã xóa hóa đơn \(record.invoice_code) khỏi app."
        do {
            _ = try await APIClient.deleteInvoice(
                apiBase: apiBase,
                token: appToken,
                request: DeleteInvoiceRequest(invoice_code: record.invoice_code, order_code: record.order_code)
            )
            statusMessage = "Đã xóa hóa đơn \(record.invoice_code) khỏi app và trang quản lý."
        } catch {
            statusMessage = "Đã xóa khỏi app. API xóa trên web báo lỗi: \(error.localizedDescription)"
        }
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

    private func dateForInvoice(_ record: SavedInvoiceRecord) -> Date? {
        if let date = record.invoice_date_vn.flatMap({ Self.dayFormatter.date(from: $0) }) {
            return date
        }
        return Self.fullFormatter.date(from: record.saved_at)
    }

    private func dateForRevenue(_ record: SavedInvoiceRecord) -> Date? {
        if let paid = record.paid_at_vn {
            if let date = Self.fullWithSecondsFormatter.date(from: paid) { return date }
            if let date = Self.fullFormatter.date(from: paid) { return date }
        }
        return dateForInvoice(record)
    }

    private func revenueForDay(_ date: Date) -> Int {
        paidInvoices.reduce(0) { sum, record in
            guard let revenueDate = dateForRevenue(record), Calendar.current.isDate(revenueDate, inSameDayAs: date) else { return sum }
            return sum + record.total_amount
        }
    }

    private func revenueForMonth(_ date: Date) -> Int {
        paidInvoices.reduce(0) { sum, record in
            guard let revenueDate = dateForRevenue(record) else { return sum }
            let cal = Calendar.current
            let a = cal.dateComponents([.year, .month], from: revenueDate)
            let b = cal.dateComponents([.year, .month], from: date)
            return a.year == b.year && a.month == b.month ? sum + record.total_amount : sum
        }
    }

    private func revenueForYear(_ date: Date) -> Int {
        paidInvoices.reduce(0) { sum, record in
            guard let revenueDate = dateForRevenue(record) else { return sum }
            return Calendar.current.component(.year, from: revenueDate) == Calendar.current.component(.year, from: date) ? sum + record.total_amount : sum
        }
    }

    private func hideKeyboard() {
        inputFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }()

    private static let fullFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "dd/MM/yyyy HH:mm"
        return formatter
    }()

    private static let fullWithSecondsFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "dd/MM/yyyy HH:mm:ss"
        return formatter
    }()
}

private struct HistoryInvoiceRow: View {
    let record: SavedInvoiceRecord
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var statusColor: Color {
        record.isPaid ? .green : .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)

                Text(record.customer_name.isEmpty ? "Khách lẻ" : record.customer_name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Text(record.isPaid ? "Đã thanh toán" : "Chưa thanh toán")
                    .font(.caption.bold())
                    .foregroundStyle(statusColor)
            }

            HStack {
                Text(record.invoice_code)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Money.format(record.total_amount))
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
            }

            HStack(spacing: 10) {
                Button {
                    onOpen()
                } label: {
                    Label("Mở", systemImage: "doc.text.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    onEdit()
                } label: {
                    Label("Sửa", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Xóa", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(statusColor.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(statusColor.opacity(0.55), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
        .onTapGesture {
            onOpen()
        }
    }
}

private struct RevenueSummaryCard: View {
    let today: Int
    let month: Int
    let year: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Báo cáo doanh thu")
                .font(.headline)
            RevenueLine(title: "Hôm nay", amount: today, color: .green)
            RevenueLine(title: "Tháng này", amount: month, color: .blue)
            RevenueLine(title: "Cả năm", amount: year, color: .purple)
        }
        .cardStyle()
    }
}

private struct RevenueLine: View {
    let title: String
    let amount: Int
    let color: Color

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(Money.format(amount))
                .font(.headline)
                .foregroundStyle(color)
        }
        .padding(10)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct MiniStatBox: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
            .foregroundStyle(status == "PAID" ? Color.green : Color.red)
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
