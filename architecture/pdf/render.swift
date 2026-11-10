import Foundation
import AppKit
import WebKit
import PDFKit

let outputURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "architecture/MetaService-hybrid-architecture.pdf")
let renderer = ArchitecturePDFRenderer(outputURL: outputURL)

final class ArchitecturePDFRenderer: NSObject, WKNavigationDelegate {
    private let outputURL: URL
    private let webView: WKWebView
    private let document = PDFDocument()
    private var renderedPages = 0

    init(outputURL: URL) {
        self.outputURL = outputURL
        self.webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 1600))
        super.init()
        webView.navigationDelegate = self
        webView.loadHTMLString(Self.pages[0], baseURL: nil)
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.run()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let configuration = WKPDFConfiguration()
        configuration.rect = NSRect(x: 0, y: 0, width: 595.28, height: 841.89)
        webView.createPDF(configuration: configuration) { result in
            switch result {
            case .failure(let error):
                FileHandle.standardError.write(Data("PDF rendering failed: \(error.localizedDescription)\n".utf8))
                exit(1)
            case .success(let data):
                guard let page = PDFDocument(data: data) else {
                    FileHandle.standardError.write(Data("PDFKit could not read a rendered page\n".utf8))
                    exit(1)
                }
                for pageIndex in 0..<page.pageCount {
                    guard let pdfPage = page.page(at: pageIndex) else { continue }
                    self.document.insert(pdfPage, at: self.document.pageCount)
                }
                self.renderedPages += 1
                guard self.renderedPages < Self.pages.count else {
                    self.document.write(to: self.outputURL)
                    let size = (try? FileManager.default.attributesOfItem(atPath: self.outputURL.path)[.size] as? Int) ?? 0
                    print("Wrote \(self.outputURL.path) (\(size) bytes, \(self.document.pageCount) pages)")
                    exit(0)
                }
                webView.loadHTMLString(Self.pages[self.renderedPages], baseURL: nil)
            }
        }
    }

    static var html: String {
        let template = #"""
    <!doctype html>
    <html><head><meta charset="utf-8"><style>
      @page { size: A4; margin: 16mm; }
      * { box-sizing: border-box; }
      body { font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; color: #241f1c; font-size: 11pt; line-height: 1.45; margin: 0; }
      .page { page-break-before: always; }
      .page:first-child { page-break-before: auto; }
      h1 { font-size: 28pt; line-height: 1.12; margin: 0 0 12pt; }
      h2 { font-size: 18pt; margin: 0 0 10pt; border-bottom: 2px solid #2e7d32; padding-bottom: 5pt; }
      h3 { font-size: 12pt; margin: 14pt 0 5pt; }
      p { margin: 0 0 8pt; }
      .subtitle { font-size: 14pt; color: #5e554e; margin-bottom: 18pt; }
      .small { font-size: 9pt; color: #665e58; }
      .note { background: #eef5ed; border-left: 4px solid #2e7d32; padding: 9pt 11pt; margin: 10pt 0; }
      .warning { background: #fff3e8; border-left: 4px solid #bf5a00; padding: 9pt 11pt; margin: 10pt 0; }
      .diagram { width: 100%; height: auto; margin: 8pt 0 12pt; }
      table { width: 100%; border-collapse: collapse; margin: 8pt 0 12pt; font-size: 9.5pt; }
      th { text-align: left; background: #e8eee7; }
      th, td { border: 1px solid #c8c2bb; padding: 5pt 6pt; vertical-align: top; }
      ul { margin: 4pt 0 10pt; padding-left: 18pt; }
      li { margin-bottom: 3pt; }
      code { font-family: Menlo, monospace; font-size: 9pt; background: #f1efec; padding: 1pt 3pt; }
      .footer { margin-top: 14pt; color: #766c63; font-size: 8pt; border-top: 1px solid #d8d1c9; padding-top: 5pt; }
    </style></head><body>

    <section class="page">
      <h1>MetaService<br>Hybrid Compute Architecture</h1>
      <p class="subtitle">On-prem machines + AWS + Liquid Compute<br>Technical overview for Kurnia and Luca · 2026-11-10</p>
      <div class="note"><b>The simple version:</b> MetaService manages the computers we own. AWS can run extra cloud/container work. Liquid Compute is a market and settlement layer—not a VM runtime.</div>
      <h3>Read this PDF</h3>
      <ul>
        <li><b>Page 2:</b> the parent, helpers, VMs, and existing services.</li>
        <li><b>Page 3:</b> Compute, sandboxes, storage, and ownership.</li>
        <li><b>Page 4:</b> the actual office cable/VLAN model.</li>
        <li><b>Page 5:</b> why the gateway and ARP test matter.</li>
        <li><b>Page 6:</b> the proposed hybrid AWS/Liquid Compute flow.</li>
        <li><b>Page 7:</b> why ECS Anywhere is the first candidate.</li>
        <li><b>Page 8:</b> phased rollout and rules for a safe proof of concept.</li>
      </ul>
      <p class="small">Architecture commit 03883a4. The AWS and Liquid Compute sections are proposals, not deployed features. No secrets or exact access addresses are included.</p>
    </section>

    <section class="page">
      <h2>1. One parent, many machines</h2>
      <p>The <b>parent</b> coordinates inventory, placement, commands, usage, and audit. A native <b>helper</b> on each machine executes local operations through a versioned contract.</p>
      __META_DIAGRAM__
      <table><tr><th>Layer</th><th>Responsibility</th></tr>
        <tr><td>Parent on Mac Mini</td><td>Panel, API, machine inventory, placement, command IDs, retries, audit, sandbox keys and usage.</td></tr>
        <tr><td>macOS helper</td><td>Swift + Apple Container for managed VMs and external-service discovery.</td></tr>
        <tr><td>Linux helper</td><td>Rust + Incus for VMs/containers; discovers existing Docker/Incus services.</td></tr>
        <tr><td>Runtime</td><td>Actually starts, stops, pauses, or deletes the workload.</td></tr>
      </table>
      <div class="note">The parent decides <b>what</b> should happen. The helper performs it on the correct machine. The runtime reports the real result.</div>
    </section>

    <section class="page">
      <h2>2. Compute and ownership</h2>
      <ul>
        <li><b>Managed workloads:</b> created by MetaService and included in its placement budgets.</li>
        <li><b>External services:</b> already running on the machine; discovered without adoption.</li>
        <li><b>Sandboxes:</b> API keys, expiration, pause/resume/kill, and usage metering.</li>
        <li><b>Storage:</b> real disk maps and classification, separate from Compute.</li>
      </ul>
      <table><tr><th>Measurement</th><th>Meaning</th></tr>
        <tr><td>Real machine memory</td><td>Actual used/cache/free, including external services and the OS.</td></tr>
        <tr><td>Managed allocation</td><td>Resources promised to managed workloads.</td></tr>
        <tr><td>Placement capacity</td><td>What MetaService may still allocate after reserves and promises.</td></tr>
      </table>
      <div class="warning"><b>Important:</b> external services never enter managed placement accounting. Two controllers must not mutate the same workload.</div>
      <h3>Current product boundaries</h3>
      <ul>
        <li>External start/stop/restart requires explicit operator action and fresh target resolution.</li>
        <li>External deletion is not offered.</li>
        <li>HTTP 202 means accepted, not finished; final command state comes from the helper.</li>
        <li>Pause, resume, and kill exist. Fork/cloning and hosted billing are not shipped.</li>
      </ul>
    </section>

    <section class="page">
      <h2>3. Office network: from cable to VLAN</h2>
      <p>The office network is a separate operational layer from MetaService. The wall-jack labels identify physical connections, not TCP ports.</p>
      __OFFICE_DIAGRAM__
      <table><tr><th>Wall jack</th><th>Switch port</th><th>Purpose</th></tr>
        <tr><td>26192-O</td><td>ge-5/0/6</td><td>Primary public connection; already working.</td></tr>
        <tr><td>26191-O</td><td>ge-5/0/1</td><td>Secondary public connection for another machine.</td></tr>
      </table>
      <h3>Two networks</h3>
      <ul>
        <li><b>Member/floor VLAN:</b> DHCP supplies a private office address.</li>
        <li><b>VLAN999:</b> static-only public connection; no DHCP address is supplied.</li>
      </ul>
      <p>The secondary test machine uses Ethernet for the public connection and WiFi for its management/default route, preserving Tailscale access while WeWork enables the port.</p>
    </section>

    <section class="page">
      <h2>4. Why gateway + ARP prove the cable path</h2>
      <p>When the Mac has the correct public static configuration, it asks the local network: “Who has the gateway?” The gateway must answer at Layer 2.</p>
      __ARP_DIAGRAM__
      <div class="warning"><b>Observed before WeWork enabled the port:</b> 100% gateway packet loss and no ARP entry. That proves there was no working public Layer-2 path. It does not tell us whether mapping, VLAN, or MAC registration was responsible.</div>
      <h3>Why WeWork asks for a MAC address</h3>
      <ul>
        <li>Locate which switch port the machine actually reaches.</li>
        <li>Check whether that port carries the member VLAN or VLAN999.</li>
        <li>Apply port security or register the device if their policy requires it.</li>
      </ul>
      <p>No local router/MikroTik is required when a machine holds the public IP directly. A router becomes useful only when we deliberately want NAT, private machine addresses, or local firewall policy.</p>
    </section>

    <section class="page">
      <h2>5. Proposed hybrid architecture</h2>
      <p>Execution, metering, and market settlement stay separate. Solid ownership boundaries prevent AWS and MetaService from managing the same workload accidentally.</p>
      __HYBRID_DIAGRAM__
      <table><tr><th>System</th><th>Role</th></tr>
        <tr><td>MetaService</td><td>On-prem Compute, ownership, VM/sandbox lifecycle, usage, and audit.</td></tr>
        <tr><td>AWS</td><td>Cloud/container jobs, S3 results/checkpoints, queues, IAM, and observability.</td></tr>
        <tr><td>Liquid Compute</td><td>Market pricing, verification, matching, settlement, and physical delivery.</td></tr>
      </table>
      <div class="note"><b>Liquid Compute is not a scheduler.</b> Its official API, authentication, supported hardware, verification format, and delivery protocol must be obtained before implementation.</div>
    </section>

    <section class="page">
      <h2>6. AWS choices</h2>
      <h3>ECS Anywhere — first hybrid-container candidate</h3>
      <ul>
        <li>One ECS control plane for compatible containers on AWS and on-prem.</li>
        <li>Uses the ECS agent, Systems Manager Agent, Docker, and external-instance registration.</li>
        <li>Requires stable internet connectivity to AWS; it is not air-gapped.</li>
        <li>Existing tasks continue during control-plane disconnect, but scaling/mutations stop and credentials can expire.</li>
        <li>GPU support still requires verification of our OS, CPU architecture, drivers, and device access.</li>
      </ul>
      <h3>Direct EC2 adapter</h3>
      <p>Use this when MetaService needs to create/delete actual cloud VMs with strict quota and cost controls. It is a separate adapter from ECS.</p>
      <h3>Not the first choice: Outposts</h3>
      <p>Outposts deploys AWS-managed infrastructure at a site. It does not simply reuse our existing Macs and PCs.</p>
      <div class="warning">ECS Anywhere does not replace the MetaService macOS helper or VM lifecycle. AWS-created tasks need explicit ownership so MetaService does not treat them as ordinary external Docker services.</div>
    </section>

    <section class="page">
      <h2>7. Safe rollout plan</h2>
      <table><tr><th>Phase</th><th>Work</th><th>Pass condition</th></tr>
        <tr><td>0. Discovery</td><td>Obtain official Liquid Compute API/participant documentation.</td><td>No unknown contract fields are invented.</td></tr>
        <tr><td>1. AWS read-only</td><td>Verify OS/CPU/GPU compatibility and estimate cost.</td><td>Written compatibility and cost evidence.</td></tr>
        <tr><td>2. One test job</td><td>One reversible, non-sensitive container job using dedicated AWS resources.</td><td>Job, logs, quotas, disconnect behavior, and rollback verified.</td></tr>
        <tr><td>3. Evidence export</td><td>Read-only verification/delivery bundle for Liquid Compute.</td><td>Validated against its real contract.</td></tr>
      </table>
      <h3>Non-negotiables</h3>
      <ul>
        <li>No production GPU interruption.</li>
        <li>No migration of existing services.</li>
        <li>No office-LAN access from proof-of-concept workloads.</li>
        <li>No credentials in Git or documents.</li>
        <li>No automatic selling, settlement, or payout in the first integration.</li>
        <li>No shared workload ownership between controllers.</li>
      </ul>
      <div class="note">The copy-ready PRD prompt is in <code>architecture/PROMPT-liquid-compute.md</code>. The detailed design and official source links are in <code>architecture/hybrid-aws-liquid-compute.md</code>.</div>
      <p class="footer">MetaService · Hybrid Compute Architecture · Native Swift/WebKit PDF</p>
    </section>
    </body></html>
    """#
        return template
            .replacingOccurrences(of: "__META_DIAGRAM__", with: metaDiagram)
            .replacingOccurrences(of: "__OFFICE_DIAGRAM__", with: officeDiagram)
            .replacingOccurrences(of: "__ARP_DIAGRAM__", with: arpDiagram)
            .replacingOccurrences(of: "__HYBRID_DIAGRAM__", with: hybridDiagram)
    }

    static var pages: [String] {
        let full = html
        let head = full.components(separatedBy: "</style>").first.map { $0 + "</style>" } ?? ""
        return full.components(separatedBy: "<section class=\"page\">").dropFirst().map { head + $0 }
    }

    static let metaDiagram = diagram(title: "MetaService request path", labels: [
        "Operator / agent", "Parent on Mac Mini", "Native helpers", "VMs / existing services",
    ], colors: ["#dce5f4", "#dcefe2", "#f6dfcf", "#e8def5"])

    static let officeDiagram = diagram(title: "Physical office connection", labels: [
        "Machine en0", "Wall jack", "Switch port", "Member VLAN / VLAN999",
    ], colors: ["#dce5f4", "#f6dfcf", "#e8def5", "#dcefe2"])

    static let arpDiagram = diagram(title: "Layer-2 proof", labels: [
        "Static public IP", "ARP: who is gateway?", "Gateway replies", "Public path test",
    ], colors: ["#dce5f4", "#fff0d9", "#f6dfcf", "#dcefe2"])

    static let hybridDiagram = diagram(title: "Hybrid on-prem + cloud + market", labels: [
        "MetaService on-prem", "AWS execution + storage", "Usage / signed evidence", "Liquid Compute market",
    ], colors: ["#dcefe2", "#dce5f4", "#fff0d9", "#e8def5"])

    static func diagram(title: String, labels: [String], colors: [String]) -> String {
        let boxes = labels.enumerated().map { index, label in
            let x = 20 + index * 225
            let arrow = index == labels.count - 1 ? "" : "<path d='M\(x + 190) 105 H\(x + 215)' stroke='#665e58' stroke-width='2'/><path d='M\(x + 209) 99 L\(x + 215) 105 L\(x + 209) 111' fill='none' stroke='#665e58' stroke-width='2'/>"
            return "<rect x='\(x)' y='65' width='190' height='80' rx='8' fill='\(colors[index])' stroke='#665e58'/><text x='\(x + 95)' y='110' text-anchor='middle' font-family='-apple-system' font-size='13' font-weight='600' fill='#241f1c'>\(label)</text>" + arrow
        }.joined()
        return "<svg class='diagram' viewBox='0 0 910 185' xmlns='http://www.w3.org/2000/svg'><text x='20' y='28' font-family='-apple-system' font-size='17' font-weight='700' fill='#241f1c'>\(title)</text>\(boxes)</svg>"
    }
}
