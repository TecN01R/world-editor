import UIKit

/// Pages to link while typing `@`, in a popover at the caret, as Apple Notes
/// shows for `>>`: this page first, then the rest with their dates, and
/// "Create page" when nothing matches by name. The keyboard stays up and
/// typing carries on; the text view keeps the caret.
final class MentionMenu: UITableViewController, UIPopoverPresentationControllerDelegate {
    struct Item {
        let title: String
        var date: Date? = nil
        var creates = false
        let action: () -> Void
    }

    /// The current page, then the others.
    var sections: [[Item]] = [] {
        didSet {
            tableView.reloadData()
            let rows = sections.reduce(0) { $0 + $1.count }
            preferredContentSize = CGSize(width: 360, height: CGFloat(min(rows, 6)) * rowHeight + CGFloat(sections.count - 1) + 12)
        }
    }

    private var rowHeight: CGFloat { UIFontMetrics.default.scaledValue(for: 48, compatibleWith: traitCollection) }

    init() {
        super.init(style: .plain)
        modalPresentationStyle = .popover
        popoverPresentationController?.delegate = self
        popoverPresentationController?.permittedArrowDirections = [.up, .down]
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = .clear   // the popover's own glass
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = rowHeight
        tableView.separatorStyle = .none   // one line only, under this page
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "page")
    }

    /// A popover on iPhone too, as in Notes, never a sheet.
    func adaptivePresentationStyle(for controller: UIPresentationController,
                                   traitCollection: UITraitCollection) -> UIModalPresentationStyle { .none }

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = sections[indexPath.section][indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "page", for: indexPath)
        var content = UIListContentConfiguration.valueCell()
        content.text = item.title
        content.secondaryText = item.date.map(Self.format)
        content.image = item.creates ? UIImage(systemName: "plus.circle") : nil
        cell.contentConfiguration = content
        cell.backgroundColor = .clear
        cell.accessibilityLabel = item.creates ? item.title : "Link to \(item.title)"
        return cell
    }

    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        section < sections.count - 1 ? 1 : 0
    }

    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard section < sections.count - 1 else { return nil }
        let line = UIView()
        line.backgroundColor = .separator
        return line
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        sections[indexPath.section][indexPath.row].action()
    }

    /// A time for today, a short date otherwise, as Notes lists them.
    private static func format(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .numeric, time: .omitted)
    }
}
