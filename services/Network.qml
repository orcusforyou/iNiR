pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Networking
import QtQuick
import qs.services.network

/**
 * Network service backed by Quickshell.Networking (D-Bus NM integration).
 * Replaces the previous nmcli-based implementation.
 */
Singleton {
    id: root

    // ── Public API (same shape as before) ────────────────────────

    property bool wifi: false
    property bool ethernet: false

    readonly property bool wifiEnabled: Networking.wifiEnabled
    property bool wifiScanning: _wifiDevice?.scannerEnabled ?? false
    property bool wifiConnecting: _connectingNetwork !== null
    property WifiAccessPoint wifiConnectTarget: null
    readonly property list<WifiAccessPoint> wifiNetworks: []
    readonly property WifiAccessPoint active: wifiNetworks.find(n => n.active) ?? null
    property string wifiStatus: "disconnected"

    property string networkName: ""
    property int networkStrength: 0
    property string materialSymbol: root.ethernet
        ? "lan"
        : root.wifiEnabled
            ? (
                root.networkStrength > 83 ? "signal_wifi_4_bar" :
                root.networkStrength > 67 ? "network_wifi" :
                root.networkStrength > 50 ? "network_wifi_3_bar" :
                root.networkStrength > 33 ? "network_wifi_2_bar" :
                root.networkStrength > 17 ? "network_wifi_1_bar" :
                "signal_wifi_0_bar"
            )
            : (root.wifiStatus === "connecting")
                ? "signal_wifi_statusbar_not_connected"
                : (root.wifiStatus === "disconnected")
                    ? "wifi_find"
                    : (root.wifiStatus === "disabled")
                        ? "signal_wifi_off"
                        : "signal_wifi_bad"

    // ── Control ──────────────────────────────────────────────────

    function enableWifi(enabled = true): void {
        Networking.wifiEnabled = enabled;
        if (enabled) rescanWifi();
    }

    function toggleWifi(): void {
        enableWifi(!Networking.wifiEnabled);
    }

    function rescanWifi(): void {
        if (!root._wifiDevice) return;
        // Toggle scanner to force rescan
        root._wifiDevice.scannerEnabled = false;
        root.wifiScanning = true;
        root._wifiDevice.scannerEnabled = true;
    }

    function connectToWifiNetwork(accessPoint: WifiAccessPoint): void {
        accessPoint.askingPassword = false;
        root.wifiConnectTarget = accessPoint;
        const net = accessPoint._qsNetwork;
        if (!net) return;
        root._connectingNetwork = net;
        net.connect();
    }

    function disconnectWifiNetwork(): void {
        const activeAp = root.active;
        if (!activeAp) return;
        const net = activeAp._qsNetwork;
        if (net) net.disconnect();
    }

    function openPublicWifiPortal(): void {
        Quickshell.execDetached(["xdg-open", "https://nmcheck.gnome.org/"])
    }

    function changePassword(network: WifiAccessPoint, password: string, username = ""): void {
        // TODO: enterprise wifi with username
        network.askingPassword = false;
        const net = network._qsNetwork;
        if (net) net.connectWithPsk(password);
    }

    // ── Internal ─────────────────────────────────────────────────

    property var _wifiDevice: null
    property var _connectingNetwork: null

    function _findWifiDevice() {
        for (const dev of Networking.devices.values) {
            if (dev.type === DeviceType.Wifi) return dev;
        }
        return null;
    }

    function _findWiredConnected(): bool {
        for (const dev of Networking.devices.values) {
            if (dev.type === DeviceType.Wired && dev.connected) return true;
        }
        return false;
    }

    function _syncState(): void {
        root._wifiDevice = root._findWifiDevice();

        // Ethernet
        root.ethernet = root._findWiredConnected();

        // Wifi status
        if (!Networking.wifiEnabled) {
            root.wifiStatus = "disabled";
            root.wifi = false;
        } else if (!root._wifiDevice) {
            root.wifiStatus = "disconnected";
            root.wifi = false;
        } else {
            const connectedNet = root._findActiveWifiNetwork();
            if (connectedNet) {
                const connectivity = Networking.connectivity;
                if (connectivity === NetworkConnectivity.Limited || connectivity === NetworkConnectivity.Portal) {
                    root.wifiStatus = "limited";
                    root.wifi = false;
                } else {
                    root.wifiStatus = "connected";
                    root.wifi = true;
                }
                root.networkName = connectedNet.name;
                root.networkStrength = Math.round(connectedNet.signalStrength * 100);
            } else {
                // Check if any network is connecting
                const connectingNet = root._findConnectingWifiNetwork();
                if (connectingNet) {
                    root.wifiStatus = "connecting";
                    root.networkName = connectingNet.name;
                    root.networkStrength = Math.round(connectingNet.signalStrength * 100);
                } else {
                    root.wifiStatus = "disconnected";
                    root.networkName = "";
                    root.networkStrength = 0;
                }
                root.wifi = false;
            }
        }
    }

    function _findActiveWifiNetwork() {
        if (!root._wifiDevice) return null;
        for (const net of root._wifiDevice.networks.values) {
            if (net.connected) return net;
        }
        return null;
    }

    function _findConnectingWifiNetwork() {
        if (!root._wifiDevice) return null;
        for (const net of root._wifiDevice.networks.values) {
            if (net.stateChanging) return net;
        }
        return null;
    }

    function _syncNetworkList(): void {
        if (!root._wifiDevice) {
            // Clear list
            const rNetworks = root.wifiNetworks;
            while (rNetworks.length > 0) rNetworks.pop().destroy();
            return;
        }

        const qsNetworks = root._wifiDevice.networks.values;
        const rNetworks = root.wifiNetworks;

        // Remove entries no longer in QS model
        const destroyed = rNetworks.filter(rn => {
            for (const qn of qsNetworks) {
                if (qn.name === rn.ssid) return false;
            }
            return true;
        });
        for (const d of destroyed)
            rNetworks.splice(rNetworks.indexOf(d), 1).forEach(n => n.destroy());

        // Add/update entries
        for (const qn of qsNetworks) {
            if (!qn.name || qn.name.length === 0) continue;
            const match = rNetworks.find(n => n.ssid === qn.name);
            if (match) {
                match._qsNetwork = qn;
                match.lastIpcObject = root._qsNetworkToIpc(qn);
            } else {
                rNetworks.push(apComp.createObject(root, {
                    _qsNetwork: qn,
                    lastIpcObject: root._qsNetworkToIpc(qn)
                }));
            }
        }
    }

    function _qsNetworkToIpc(qn): var {
        return {
            ssid: qn.name ?? "",
            bssid: "",
            strength: Math.round((qn.signalStrength ?? 0) * 100),
            frequency: 0,
            active: qn.connected ?? false,
            security: (qn.security !== undefined && qn.security !== WifiSecurityType.None)
                ? WifiSecurityType.toString(qn.security) : ""
        };
    }

    // ── Reactivity ───────────────────────────────────────────────

    Timer {
        id: _syncDebounce
        interval: 50
        repeat: false
        onTriggered: {
            root._syncState();
            root._syncNetworkList();
        }
    }

    function _scheduleSync(): void {
        _syncDebounce.restart();
    }

    Connections {
        target: Networking
        function onWifiEnabledChanged() { root._scheduleSync() }
        function onConnectivityChanged() { root._scheduleSync() }
    }

    // Watch the wifi device's network model for changes
    Connections {
        target: root._wifiDevice?.networks ?? null
        function onValuesChanged() { root._scheduleSync() }
    }

    // Watch devices list for device add/remove
    Connections {
        target: Networking.devices
        function onValuesChanged() { root._scheduleSync() }
    }

    // Handle connection failure → prompt for password
    Connections {
        target: root._connectingNetwork
        function onConnectionFailed(reason) {
            if (reason === ConnectionFailReason.NoSecrets && root.wifiConnectTarget) {
                root.wifiConnectTarget.askingPassword = true;
            }
            root._connectingNetwork = null;
        }
        function onConnectedChanged() {
            if (root._connectingNetwork?.connected) {
                if (root.wifiConnectTarget) {
                    root.wifiConnectTarget.askingPassword = false;
                    root.wifiConnectTarget = null;
                }
                root._connectingNetwork = null;
            }
        }
        function onStateChanged() {
            // Connection attempt finished (either connected or failed back to disconnected)
            if (root._connectingNetwork && !root._connectingNetwork.stateChanging) {
                root._connectingNetwork = null;
            }
        }
    }

    Component.onCompleted: {
        root._syncState();
        root._syncNetworkList();
        // Enable scanner so networks appear
        if (root._wifiDevice) root._wifiDevice.scannerEnabled = true;
    }

    Component {
        id: apComp
        WifiAccessPoint {}
    }
}
