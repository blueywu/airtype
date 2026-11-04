/// Compatibility preserves the upstream always-running engine. On-demand
/// mode owns audio resources only for an active, non-muted voice session.
struct AudioResourcePolicy: Equatable {
    let output: Bool
    let microphone: Bool

    init(onDemand: Bool, active: Bool, mac: Bool, remote: Bool) {
        output = !onDemand || (active && (mac || remote))
        microphone = mac && (!onDemand || active)
    }
}
