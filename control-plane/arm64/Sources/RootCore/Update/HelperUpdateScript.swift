import Foundation

public enum HelperUpdateScriptError: Error, Equatable {
    case badBuild
}

/// What an update answers the panel: one of three names and a sentence in plain words.
public struct HelperUpdateResult: Encodable, Equatable {
    public let result: String
    public let message: String
}

/// The one script that replaces a helper program inside its box, and the reading of what it answers. The new program arrives on the script's standard input.
/// The script holds the box folder and the port (both stored when the machine was added), and the checksum the parent computed itself: nothing from a request.
/// It answers with one line, `ms-code: <word>`; only that word is read, so text from the other computer never reaches the panel.
public enum HelperUpdateScript {
    /// How long the new helper gets before it is looked at.
    public static let settleSeconds = 8
    /// How long the old helper gets to stop before the update gives up (nothing has been changed by then).
    public static let stopWaitSeconds = 10
    /// How long the loopback check waits for an answer.
    public static let answerSeconds = 3
    static let codeMarker = "ms-code:"

    public static func make(box: String, agentPort: Int, expectedBuild: String) throws -> String {
        guard AgentBuild.isValid(expectedBuild) else { throw HelperUpdateScriptError.badBuild }
        return #"""
        set -u
        umask 077
        box=\#(Shell.quote(box)); port=\#(agentPort); want=\#(Shell.quote(expectedBuild))
        say() { printf 'ms-code: %s\n' "$1"; exit 0; }
        sum() { { shasum -a 256 "$1" 2>/dev/null || sha256sum "$1" 2>/dev/null; } | cut -d' ' -f1; }
        alive() {
          pid=$(cat state/agent.pid 2>/dev/null) || return 1
          [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || return 1
          if command -v curl >/dev/null 2>&1; then
            code=$(curl -s -o /dev/null -m \#(answerSeconds) -w '%{http_code}' "http://127.0.0.1:$port/" 2>/dev/null); [ -n "$code" ] && [ "$code" != 000 ]; return
          fi
          if command -v nc >/dev/null 2>&1; then nc -z 127.0.0.1 "$port" >/dev/null 2>&1; return; fi
          return 0
        }
        cd "$box" 2>/dev/null || say no_box
        grep -q '"made_by":"metaservice"' manifest.json 2>/dev/null || say not_ours
        [ -f bin/metaservice-agent ] || say no_box
        [ -n "$(sum bin/metaservice-agent)" ] || say no_checker
        rm -f bin/metaservice-agent.new
        cat > bin/metaservice-agent.new || { rm -f bin/metaservice-agent.new; say receive_failed; }
        [ "$(sum bin/metaservice-agent.new)" = "$want" ] || { rm -f bin/metaservice-agent.new; say checksum; }
        chmod 700 bin/metaservice-agent.new
        short=$(sum bin/metaservice-agent | cut -c1-8); [ -n "$short" ] || short=old
        keep="bin/metaservice-agent.before-$short"
        cp -p bin/metaservice-agent "$keep" || { rm -f bin/metaservice-agent.new; say keep_failed; }
        for older in bin/metaservice-agent.before-*; do [ "$older" = "$keep" ] || rm -f "$older"; done
        oldpid=$(cat state/agent.pid 2>/dev/null || true)
        [ ! -x ./stop.sh ] || sh ./stop.sh
        waited=0
        while [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null && [ "$waited" -lt \#(stopWaitSeconds) ]; do sleep 1; waited=$((waited + 1)); done
        if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then rm -f bin/metaservice-agent.new; say stop_failed; fi
        mv -f bin/metaservice-agent.new bin/metaservice-agent
        sh ./start.sh >/dev/null 2>&1 || true
        sleep \#(settleSeconds)
        alive && say updated
        [ ! -x ./stop.sh ] || sh ./stop.sh
        sleep 1
        cp -p "$keep" bin/metaservice-agent
        sh ./start.sh >/dev/null 2>&1 || true
        sleep \#(settleSeconds)
        alive && say rolled_back
        say rollback_failed

        """#
    }

    private struct Answer {
        let result: String
        let message: String
    }

    private static let answers: [String: Answer] = [
        "updated": Answer(result: "updated", message: "The helper was replaced with the newest one and it is running. Your VMs keep running."),
        "rolled_back": Answer(result: "rolled_back", message: "The new helper did not start, so the old one was put back and is running again. Nothing was lost."),
        "rollback_failed": Answer(result: "failed", message: "The new helper did not start and the old one could not be put back. Look at logs/agent.log in the MetaService folder on that computer."),
        "checksum": Answer(result: "failed", message: "The program that arrived is not the one that was sent (its checksum is different). Nothing was changed."),
        "receive_failed": Answer(result: "failed", message: "The program could not be copied to that computer. Nothing was changed."),
        "not_ours": Answer(result: "failed", message: "That folder is not a MetaService box, so nothing was changed."),
        "no_box": Answer(result: "failed", message: "The MetaService folder or its program is not on that computer any more. Remove the machine and add it again."),
        "no_checker": Answer(result: "failed", message: "That computer has neither shasum nor sha256sum, so the copy cannot be checked. Nothing was changed."),
        "keep_failed": Answer(result: "failed", message: "The old program could not be kept as a copy, so nothing was changed."),
        "stop_failed": Answer(result: "failed", message: "The old helper did not stop in time, so nothing was changed."),
    ]
    private static let unknown = Answer(result: "failed", message: "That computer did not give an answer the parent understands. Look at logs/agent.log in the MetaService folder on that computer.")

    /// Every word the script can end with.
    public static var codes: [String] { Array(answers.keys).sorted() }

    /// The last known `ms-code:` word of the output, or "unknown". It is the only part of the output that is ever kept (the audit log holds it).
    public static func code(in output: String) -> String {
        let words = output.split(whereSeparator: \.isNewline).filter { $0.hasPrefix(codeMarker) }
        guard let word = words.last.map({ $0.dropFirst(codeMarker.count).trimmingCharacters(in: .whitespaces) }), answers[word] != nil else { return "unknown" }
        return word
    }

    /// The last `ms-code:` word of the output, turned into the answer. A missing or unknown word is a failure; the other computer's own text is never passed on.
    public static func outcome(output: String) -> HelperUpdateResult {
        let answer = answers[code(in: output)] ?? unknown
        return HelperUpdateResult(result: answer.result, message: answer.message)
    }
}
