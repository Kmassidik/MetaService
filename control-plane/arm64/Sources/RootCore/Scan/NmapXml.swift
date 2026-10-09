import Foundation

/// Reads `nmap -oX -` output. Only what the scan needs: address, MAC, vendor, host name, and one open port.
public enum NmapXml {
    public static func hosts(from xml: Data, agentPort: Int?) -> [NmapHost] {
        let reader = Reader(agentPort: agentPort)
        let parser = XMLParser(data: xml)
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        parser.parse()
        return reader.hosts
    }

    private final class Reader: NSObject, XMLParserDelegate {
        let agentPort: Int?
        var hosts: [NmapHost] = []
        private var current: Draft?

        private struct Draft {
            var up = false
            var ip: String?
            var mac: String?
            var vendor: String?
            var hostname: String?
            var portOpen = false
        }

        init(agentPort: Int?) { self.agentPort = agentPort }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes attrs: [String: String]) {
            switch name {
            case "host": current = Draft()
            case "status": current?.up = attrs["state"] == "up"
            case "address": readAddress(attrs)
            case "hostname": readHostname(attrs)
            case "port": readPort(attrs)
            case "state": readPortState(attrs)
            default: break
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            guard name == "host", let draft = current else { return }
            current = nil
            guard draft.up, let ip = draft.ip, Subnet.address(ip) != nil else { return }
            hosts.append(NmapHost(ip: ip, mac: draft.mac.flatMap(MacAddress.normalize), vendor: draft.vendor, hostname: draft.hostname, agentPortOpen: draft.portOpen))
        }

        private var inAgentPort = false

        private func readHostname(_ attrs: [String: String]) {
            guard current?.hostname == nil else { return }
            current?.hostname = attrs["name"]
        }

        private func readAddress(_ attrs: [String: String]) {
            switch attrs["addrtype"] {
            case "ipv4": current?.ip = attrs["addr"]
            case "mac":
                current?.mac = attrs["addr"]
                current?.vendor = attrs["vendor"]
            default: break
            }
        }

        private func readPort(_ attrs: [String: String]) {
            inAgentPort = agentPort != nil && attrs["protocol"] == "tcp" && attrs["portid"] == agentPort.map(String.init)
        }

        private func readPortState(_ attrs: [String: String]) {
            guard inAgentPort, attrs["state"] == "open" else { return }
            current?.portOpen = true
            inAgentPort = false
        }
    }
}
