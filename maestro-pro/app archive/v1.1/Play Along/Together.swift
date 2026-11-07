import SwiftUI
import MultipeerConnectivity
import UIKit

// Several devices (up to eight) playing the same piece in time, each from its own sheet music (a flute part and a clarinet part,
// a PDF and a MusicXML file, different keys). Positions are sent as bars, not beats or notes, so any two
// parts with the same bars line up. They find each other over Bluetooth/Wi-Fi (no internet or
// account needed), agree on a shared clock, and every play, pause, seek and tempo change is sent with the
// moment it should happen, so both start on the same beat of the same clock. The host sends its position
// once a second and a device that has drifted snaps back.
// ponytail: with a backing track the audio is the master clock on each device, so tracks aren't re-aligned
// mid-piece (they start together and drift by a few ms per minute at most). Wireless speakers add their own
// delay: the Nudge slider moves this device's sound earlier or later to match.

nonisolated enum SyncMessage: Codable {
    case hello(title: String, bars: Int, lyrics: Bool)
    case ping(t0: Double)
    case pong(t0: Double, th: Double)
    // Positions are bars (2.5 is halfway through bar 3), and seconds into the song for a lyrics screen, which has no bars.
    case play(bar: Double, sec: Double, at: Double, tempo: Double, speed: Double)
    case pause(bar: Double, sec: Double)
    case seek(bar: Double, sec: Double, playing: Bool, at: Double)
    case tempo(Double)
    case speed(Double)
    case heartbeat(bar: Double, sec: Double, at: Double)

    /// The same message with every clock time moved by `d` seconds.
    func shifted(by d: Double) -> SyncMessage {
        switch self {
        case .pong(let t0, let th): .pong(t0: t0, th: th + d)
        case .play(let b, let sec, let at, let t, let s): .play(bar: b, sec: sec, at: at + d, tempo: t, speed: s)
        case .seek(let b, let sec, let p, let at): .seek(bar: b, sec: sec, playing: p, at: at + d)
        case .heartbeat(let b, let sec, let at): .heartbeat(bar: b, sec: sec, at: at + d)
        default: self
        }
    }
}

@Observable final class Together: NSObject {
    enum Mode { case idle, hosting, browsing }

    private(set) var mode = Mode.idle
    private(set) var connected = false
    private(set) var peerName: String?
    private(set) var nearby: [MCPeerID] = []
    /// Players waiting to be let in; the sheet asks about the first.
    @ObservationIgnored private var invitations: [(name: String, answer: (Bool) -> Void)] = []
    var invitation: (name: String, answer: (Bool) -> Void)?
    /// Everyone connected to this device (a guest is connected to the host only; the host passes messages between guests).
    private(set) var peerNames: [String] = []
    private(set) var status = ""
    /// Their clock minus ours, in seconds, from the best round trip so far (the guest measures; the host is 0).
    private(set) var offset = 0.0
    /// Half the best round trip: how far off the shared clock can be.
    private(set) var accuracy: Double?
    /// The part the other player has open, and how many bars it has.
    private(set) var remoteTitle: String?
    private(set) var remoteBars = 0
    /// The other device has lyrics open, not sheet music: positions go between you in seconds.
    private(set) var remoteLyrics = false
    /// Moves this device's sound earlier (+) or later (−), in seconds, to match wireless speakers.
    var nudge = 0.0
    var title = ""
    var bars = 0
    var lyrics = false
    @ObservationIgnored weak var transport: Transport?

    #if DEBUG
    @ObservationIgnored weak var loopback: Together?
    func markConnectedForTest() { connected = true }
    #endif
    @ObservationIgnored private let me = MCPeerID(displayName: UIDevice.current.name)
    @ObservationIgnored private var session: MCSession?
    @ObservationIgnored private var advertiser: MCNearbyServiceAdvertiser?
    @ObservationIgnored private var browser: MCNearbyServiceBrowser?
    @ObservationIgnored private var best = (rtt: Double.infinity, at: 0.0)
    @ObservationIgnored private var timer: Timer?
    private static let service = "playalong-sync"

    var now: Double { CACurrentMediaTime() }

    // MARK: Starting and stopping

    func host() {
        Analytics.track("together_host")
        stop()
        mode = .hosting
        status = String(localized: "Waiting for another player to join…")
        let s = makeSession()
        advertiser = MCNearbyServiceAdvertiser(peer: me, discoveryInfo: nil, serviceType: Self.service)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
        session = s
    }

    func browse() {
        Analytics.track("together_join")
        stop()
        mode = .browsing
        status = String(localized: "Looking for a player who is hosting…")
        session = makeSession()
        browser = MCNearbyServiceBrowser(peer: me, serviceType: Self.service)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
    }

    func join(_ peer: MCPeerID) {
        guard let session else { return }
        status = String(localized: "Joining \(peer.displayName)…")
        browser?.invitePeer(peer, to: session, withContext: nil, timeout: 20)
    }

    func stop() {
        advertiser?.stopAdvertisingPeer(); browser?.stopBrowsingForPeers()
        session?.disconnect()
        invitations = []; invitation = nil; peerNames = []
        advertiser = nil; browser = nil; session = nil
        timer?.invalidate(); timer = nil
        mode = .idle; connected = false; peerName = nil; nearby = []; remoteTitle = nil; accuracy = nil; offset = 0
        best = (.infinity, 0)
        status = ""
    }

    private func makeSession() -> MCSession {
        let s = MCSession(peer: me, securityIdentity: nil, encryptionPreference: .required)
        s.delegate = self
        return s
    }

    // MARK: Messages

    /// Times in a message are on the sender's clock; they go out on the host's clock.
    func send(_ message: SyncMessage, reliably: Bool = true, to peers: [MCPeerID]? = nil) {
        #if DEBUG
        if let other = loopback { Task { @MainActor in other.receive(message) }; return }   // test: two Together objects in one process
        #endif
        guard let session, case let targets = peers ?? session.connectedPeers, !targets.isEmpty,
              let data = try? JSONEncoder().encode(message.shifted(by: mode == .browsing ? offset : 0)) else { return }
        try? session.send(data, toPeers: targets, with: reliably ? .reliable : .unreliable)
    }

    private func receive(_ wire: SyncMessage, from peer: MCPeerID? = nil) {
        // The host is the hub: what one guest does reaches the others (times already on the host's clock).
        if mode == .hosting, let peer, let session {
            switch wire {
            case .ping, .pong, .heartbeat: break
            default: send(wire, to: session.connectedPeers.filter { $0 != peer })
            }
        }
        // Back onto this device's clock. (A pong carries the host's time as is.)
        let message: SyncMessage
        if case .pong = wire { message = wire } else { message = wire.shifted(by: mode == .browsing ? -offset : 0) }
        switch message {
        case .hello(let t, let n, let l): remoteTitle = t; remoteBars = n; remoteLyrics = l
        case .ping(let t0): send(.pong(t0: t0, th: now), reliably: false, to: peer.map { [$0] })   // sent as is: th is already the host's clock
        case .pong(let t0, let th):
            let t3 = now, rtt = t3 - t0
            if rtt < best.rtt || t3 - best.at > 30 {
                best = (rtt, t3)
                offset = th - (t0 + t3) / 2
                accuracy = rtt / 2
            }
        case .heartbeat(let bar, let sec, let at): transport?.resync(toBar: bar, sec: sec, age: now - at)
        default: transport?.apply(message)
        }
    }

    /// Tells the other device which part is open here (call again when it changes).
    func sendHello() { send(.hello(title: title, bars: bars, lyrics: lyrics)) }

    private func linked(_ peers: [MCPeerID]) {
        let first = connected
        connected = !peers.isEmpty
        peerNames = peers.map(\.displayName)
        peerName = peerNames.joined(separator: ", ")
        timer?.invalidate()
        guard connected else { remoteTitle = nil; status = mode == .hosting ? String(localized: "Waiting for another player to join…") : "Disconnected."; return }
        browser?.stopBrowsingForPeers()   // a host keeps advertising so more players can join
        status = String(localized: "Connected to \(peerName!).")
        sendHello()
        if mode == .browsing, !first {
            // Measure the clock difference: many quick round trips, keeping the fastest.
            best = (.infinity, 0)
            for i in 0..<20 { DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.05) { [weak self] in self.map { $0.send(.ping(t0: $0.now), reliably: false) } } }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.mode == .hosting, let t = self.transport, t.isPlaying { self.send(.heartbeat(bar: t.barPosition(t.beat), sec: t.songTime(t.beat), at: self.now), reliably: false) }
                if self.mode == .browsing, Int(self.now) % 15 == 0 { self.send(.ping(t0: self.now), reliably: false) }
            }
        }
    }
}

extension Together: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected, .notConnected: if state == .connected || connected { linked(session.connectedPeers) }
            default: break
            }
        }
    }
    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? JSONDecoder().decode(SyncMessage.self, from: data) else { return }
        Task { @MainActor in receive(message, from: peerID) }
    }
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension Together: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            #if DEBUG
            if CommandLine.arguments.contains("-togetherHost") { invitationHandler(true, session); return }
            #endif
            if (session?.connectedPeers.count ?? 0) >= 7 { invitationHandler(false, nil); return }   // MultipeerConnectivity allows eight devices
            invitations.append((peerID.displayName, { ok in
                self.invitations.removeFirst()
                self.invitation = self.invitations.first
                invitationHandler(ok, ok ? self.session : nil)
            }))
            invitation = invitations.first
        }
    }
}

extension Together: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            if !nearby.contains(peerID) { nearby.append(peerID) }
            #if DEBUG
            if CommandLine.arguments.contains("-togetherJoin") { join(peerID) }
            #endif
        }
    }
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in nearby.removeAll { $0 == peerID } }
    }
}

// MARK: - Sheet

struct TogetherView: View {
    @Bindable var together: Together
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "person.2.wave.2.fill").font(.system(size: 44)).foregroundStyle(Theme.accent)
            Text("Play Together").font(.title2.bold())
            switch together.mode {
            case .idle:
                Text("Link up to eight devices so everyone plays the same piece exactly in time, each from their own sheet music: a flute part, a clarinet part, a different key or instrument. Open your parts, then one person starts a session and the others join.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Start a Session") { together.host() }.buttonStyle(.borderedProminent)
                Button("Join a Session") { together.browse() }.buttonStyle(.bordered)
            case .hosting, .browsing:
                if together.connected {
                    Label(together.status, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    if let a = together.accuracy {
                        Text("Clocks agree to within \(max(1, Int((a * 1000).rounded()))) ms.").font(.callout).foregroundStyle(.secondary)
                    }
                    if let theirs = together.remoteTitle {
                        Text(together.peerNames.count > 1 ? "\(together.peerNames.count) players are connected. Each of you keeps your own sheet music and instrument; you stay together bar by bar." : String(localized: "They’re playing “\(theirs)”. Each of you keeps your own sheet music and instrument; you stay together bar by bar."))
                            .font(.callout).foregroundStyle(.secondary)
                        if together.remoteBars != together.bars, together.bars > 0, !together.lyrics, !together.remoteLyrics {
                            Label("Their part has \(together.remoteBars) bars and yours has \(together.bars), so the two may drift apart.", systemImage: "exclamationmark.triangle.fill").font(.callout)
                        }
                    }
                    VStack(alignment: .leading) {
                        Text("Nudge sound: \(Int((together.nudge * 1000).rounded())) ms").font(.callout)
                        Slider(value: $together.nudge, in: -0.15...0.15, step: 0.005).tint(Theme.accent)
                        Text("If you use wireless speakers or headphones and the sound runs behind the other player, move it earlier.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    ProgressView()
                    Text(together.status).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    ForEach(together.nearby, id: \.self) { peer in
                        Button(peer.displayName) { together.join(peer) }.buttonStyle(.borderedProminent)
                    }
                }
                Button(together.connected ? "Disconnect" : "Cancel", role: .destructive) { together.stop() }
            }
            Button("Done") { dismiss() }
        }
        .padding(30)
        .frame(minWidth: 340, minHeight: 360)
        .alert("Let \(together.invitation?.name ?? "someone") join?", isPresented: .constant(together.invitation != nil)) {
            Button("Allow") { together.invitation?.answer(true) }
            Button("Decline", role: .cancel) { together.invitation?.answer(false) }
        } message: { Text("They’ll be able to start, pause and move through the music with you.") }
    }
}
