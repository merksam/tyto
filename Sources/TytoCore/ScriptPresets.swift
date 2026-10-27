import Foundation

public enum Shell {
    /// POSIX single quotes: nothing inside is special to sh except the quote itself, which
    /// becomes '\''. Spaces, $(...), backticks, globs and newlines all stay literal.
    public static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}

public struct PresetField: Hashable, Identifiable, Sendable {
    public enum Kind: Hashable, Sendable {
        case text
        case url
        case number(ClosedRange<Int>)
    }

    public let key: String
    public let label: String
    public let placeholder: String
    public let help: String?
    public let isRequired: Bool
    public let kind: Kind
    public let defaultValue: String

    public var id: String { key }

    init(_ key: String, _ label: String, placeholder: String = "", help: String? = nil,
         required: Bool = false, kind: Kind = .text, defaultValue: String = "") {
        self.key = key; self.label = label; self.placeholder = placeholder; self.help = help
        self.isRequired = required; self.kind = kind; self.defaultValue = defaultValue
    }
}

/// The scripts Tyto can write for the user. Each is a template whose fields are filled in with
/// shell-quoted values, so whatever is typed into a field lands in the script as one literal
/// string and can never become code.
public enum PresetID: String, Codable, CaseIterable, Sendable {
    case ssh, s3, webhook, custom

    public var title: String {
        switch self {
        case .ssh: "SSH"
        case .s3: "S3-compatible"
        case .webhook: "Webhook"
        case .custom: "Custom script"
        }
    }

    public var summary: String {
        switch self {
        case .ssh: "Copies the capture to a folder on another machine with scp, using your ~/.ssh setup. The clipboard gets its path there, or a link if you give a base URL."
        case .s3: "Uploads with the aws CLI and your aws profile, to AWS or anything S3-compatible: R2, B2, MinIO. The clipboard gets a public or presigned link."
        case .webhook: "Posts the capture to a URL with curl. A token, if needed, is read from your login keychain. The clipboard gets the link from the JSON reply."
        case .custom: "A commented script to write yourself. Whatever it prints first is the result."
        }
    }

    public var fields: [PresetField] {
        switch self {
        case .ssh:
            [PresetField("host", "Host", placeholder: "devbox", help: "A host name or an alias from ~/.ssh/config.", required: true),
             PresetField("folder", "Remote folder", placeholder: "clips", help: "Relative to the remote home folder unless it starts with /.", required: true),
             PresetField("baseURL", "Base URL", placeholder: "https://example.com/clips", help: "Optional. If the folder is served on the web, the clipboard gets this plus the file name instead of the path.", kind: .url)]
        case .s3:
            [PresetField("bucket", "Bucket", placeholder: "my-screenshots", required: true),
             PresetField("prefix", "Prefix", placeholder: "tyto/", help: "Optional folder inside the bucket."),
             PresetField("endpoint", "Endpoint", placeholder: "https://<account>.r2.cloudflarestorage.com", help: "Only for R2, B2, MinIO and the like. Empty means AWS.", kind: .url),
             PresetField("profile", "aws profile", placeholder: "default", help: "From ~/.aws; holds the keys and the region. Empty means the default profile."),
             PresetField("publicBaseURL", "Public base URL", placeholder: "https://shots.example.com", help: "If the bucket is public. Empty means a presigned link.", kind: .url),
             PresetField("expiresIn", "Presigned link lasts", placeholder: "604800", help: "Seconds; 604800 is seven days, the most AWS allows.", kind: .number(1...604_800), defaultValue: "604800")]
        case .webhook:
            [PresetField("url", "URL", placeholder: "https://example.com/upload", help: "The capture is posted as multipart form data in a field named file.", required: true, kind: .url),
             PresetField("keychainItem", "Keychain item", placeholder: "tyto-webhook", help: "Optional. The name of a password item in your login keychain holding a bearer token."),
             PresetField("jsonField", "Link field", placeholder: "url", help: "Where the link is in the JSON reply, such as url or data.link. Empty means the whole reply.", defaultValue: "url")]
        case .custom:
            []
        }
    }

    /// The trimmed values for every field, with defaults where nothing was given.
    public func normalized(_ values: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        for f in fields {
            let v = (values[f.key] ?? "").trimmingCharacters(in: .whitespaces)
            out[f.key] = v.isEmpty ? f.defaultValue : v
        }
        return out
    }

    /// Problems by field key; empty means the values can be saved.
    public func validate(_ values: [String: String]) -> [String: String] {
        var problems: [String: String] = [:]
        let values = normalized(values)
        for f in fields {
            let v = values[f.key] ?? ""
            if v.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
                problems[f.key] = "Must be a single line."
            } else if v.isEmpty {
                if f.isRequired { problems[f.key] = "Required." }
            } else {
                switch f.kind {
                case .text:
                    break
                case .url:
                    let lower = v.lowercased()
                    if !(lower.hasPrefix("https://") || lower.hasPrefix("http://")) {
                        problems[f.key] = "Must start with https:// or http://."
                    }
                case .number(let range):
                    if Int(v).map(range.contains) != true {
                        problems[f.key] = "A whole number from \(range.lowerBound) to \(range.upperBound)."
                    }
                }
            }
        }
        return problems
    }

    /// What a new destination is called if the user leaves the name empty.
    public func suggestedName(_ values: [String: String]) -> String {
        let values = normalized(values)
        switch self {
        case .ssh: return values["host"].flatMap { $0.isEmpty ? nil : $0 } ?? "SSH"
        case .s3: return values["bucket"].flatMap { $0.isEmpty ? nil : $0 } ?? "S3"
        case .webhook: return values["url"].flatMap { URLComponents(string: $0)?.host } ?? "Webhook"
        case .custom: return "Custom"
        }
    }

    /// The script for these values. Every placeholder is replaced by a shell-quoted value in a
    /// single pass, so a value that happens to look like a placeholder stays text.
    public func render(_ values: [String: String]) -> String {
        let values = normalized(values)
        let template = Self.header(title: title, about: about, rewrites: self != .custom) + "\n" + body
        var out = ""
        var rest = Substring(template)
        while let open = rest.range(of: "{{") {
            out += rest[..<open.lowerBound]
            guard let close = rest[open.upperBound...].range(of: "}}") else {
                rest = rest[open.lowerBound...]
                break
            }
            out += Shell.quote(values[String(rest[open.upperBound..<close.lowerBound])] ?? "")
            rest = rest[close.upperBound...]
        }
        return out + rest
    }

    /// The placeholder names in the template, for the test that each has a field.
    var placeholders: Set<String> {
        var names = Set<String>()
        var rest = Substring(body)
        while let open = rest.range(of: "{{"), let close = rest[open.upperBound...].range(of: "}}") {
            names.insert(String(rest[open.upperBound..<close.lowerBound]))
            rest = rest[close.upperBound...]
        }
        return names
    }

    // MARK: Templates

    private var about: String {
        switch self {
        case .ssh: """
            # Copies the capture into a folder on another machine with scp and prints where it
            # landed: the remote path, or a link when a base URL is set. It runs as you, with your
            # own ~/.ssh config, keys and agent; Tyto never sees any of them.
            """
        case .s3: """
            # Uploads the capture with the aws CLI and prints a link to it: under the public base
            # URL when one is set, otherwise a presigned link that expires. Works with AWS and,
            # through the endpoint, with R2, B2, MinIO and the like. Credentials come from your aws
            # profile in ~/.aws; Tyto never sees them.
            """
        case .webhook: """
            # Posts the capture to a URL with curl, as multipart form data in a field named file,
            # and prints the link from the JSON reply. A bearer token, if the service needs one,
            # is read from your login keychain, so it is never in this file or in Tyto. Store it
            # once with:  security add-generic-password -s <keychain item> -a "$USER" -w
            """
        case .custom: """
            # A starting point for your own destination: copy the file anywhere, upload it with
            # any tool, and print what should be pasted afterwards.
            """
        }
    }

    private static func header(title: String, about: String, rewrites: Bool) -> String {
        let origin = rewrites
            ? """
              # Written by Tyto from Settings → Destinations, and written again when you change
              # its fields there.
              """
            : """
              # Written once by Tyto from Settings → Destinations; edit it freely, Tyto will not
              # write it again.
              """
        return """
        #!/bin/sh
        # Tyto destination: \(title)
        #
        \(about)
        #
        \(origin)
        #
        # How Tyto runs it: $1 is the capture, a PNG file; $2 is a suggested name for it without
        # spaces, tyto-YYYYMMDD-HHMMSS.png. The first line printed is the result, and goes on the
        # clipboard. Any exit other than 0 is a failure, shown with the last line of stderr.
        # Tyto waits 60 seconds at most. It runs as you, outside Tyto's sandbox, with a minimal
        # PATH: give tools from Homebrew and the like their full path.
        set -eu

        """
    }

    private var body: String {
        switch self {
        case .ssh: #"""
            host={{host}}
            folder={{folder}}
            base_url={{baseURL}}

            file=$1
            name=$2

            # ssh and scp both start in the remote home, so a leading ~/ is the same as none.
            dir=${folder#\~/}
            if [ -z "$dir" ] || [ "$dir" = '~' ]; then dir=.; fi

            # Quotes a value for the remote shell, which reads the ssh command line again.
            remote_quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

            # The folder is usually there already, so try the copy alone first: one connection.
            if ! scp -q -o BatchMode=yes -o ConnectTimeout=20 -- "$file" "$host:$dir/$name" 2>/dev/null; then
              ssh -o BatchMode=yes -o ConnectTimeout=20 -- "$host" "mkdir -p -- $(remote_quote "$dir")"
              scp -q -o BatchMode=yes -o ConnectTimeout=20 -- "$file" "$host:$dir/$name"
            fi

            if [ -n "$base_url" ]; then
              printf '%s/%s\n' "${base_url%/}" "$name"
            else
              case $folder in
                /*|'~'|'~/'*) printf '%s/%s\n' "${folder%/}" "$name" ;;
                *) printf '~/%s/%s\n' "${folder%/}" "$name" ;;
              esac
            fi

            """#
        case .s3: #"""
            bucket={{bucket}}
            prefix={{prefix}}
            endpoint={{endpoint}}
            profile={{profile}}
            public_base_url={{publicBaseURL}}
            expires_in={{expiresIn}}

            # The aws CLI usually lives in one of these, which a script's PATH does not include.
            PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"

            file=$1
            name=$2

            prefix=${prefix#/}
            prefix=${prefix%/}
            key=${prefix:+$prefix/}$name

            set --
            if [ -n "$profile" ]; then set -- "$@" --profile "$profile"; fi
            if [ -n "$endpoint" ]; then set -- "$@" --endpoint-url "$endpoint"; fi

            # Progress goes to stderr: the first line on stdout must be the link.
            aws "$@" s3 cp --only-show-errors --content-type image/png "$file" "s3://$bucket/$key" >&2

            if [ -n "$public_base_url" ]; then
              printf '%s/%s\n' "${public_base_url%/}" "$key"
            else
              aws "$@" s3 presign "s3://$bucket/$key" --expires-in "$expires_in"
            fi

            """#
        case .webhook: #"""
            url={{url}}
            keychain_item={{keychainItem}}
            json_field={{jsonField}}

            file=$1
            name=$2

            token=
            if [ -n "$keychain_item" ]; then
              token=$(security find-generic-password -s "$keychain_item" -w) || {
                echo "no password item named $keychain_item in the login keychain" >&2
                exit 1
              }
            fi

            # The header goes in on stdin, so the token never shows in the process list.
            response=$(
              if [ -n "$token" ]; then printf 'Authorization: Bearer %s\n' "$token"; fi |
                curl --silent --show-error --fail-with-body --max-time 50 \
                  -H @- -F "file=@$file;type=image/png;filename=$name" -- "$url"
            )

            if [ -z "$json_field" ]; then
              printf '%s\n' "$response"
              exit 0
            fi
            link=$(printf '%s' "$response" | plutil -extract "$json_field" raw -o - -) || {
              echo "the reply has no $json_field field" >&2
              exit 1
            }
            printf '%s\n' "$link"

            """#
        case .custom: #"""
            file=$1
            name=$2

            # Some starting points; replace the last line with one of them, or anything else:
            #   rsync -q "$file" "server:/var/www/shots/$name" && echo "https://example.com/shots/$name"
            #   rclone copyto "$file" "remote:shots/$name" && rclone link "remote:shots/$name"
            #   /opt/homebrew/bin/gh gist create "$file"

            printf '%s\n' "$file"

            """#
        }
    }
}
