package handlers

import "testing"

func TestHubDisconnectFamilyUserClosesOnlyFamilySockets(t *testing.T) {
	h := newHub()
	first := testWSClient()
	second := testWSClient()
	otherUser := testWSClient()
	admin := testWSClient()

	// Multiple app instances can be connected at once. Use two family IDs to
	// prove every tracked family socket for the moved user is removed, while an
	// unrelated family member and a platform-admin stream stay connected.
	h.register("family-old", "moved-user", first)
	h.register("family-new", "moved-user", second)
	h.register("family-old", "other-user", otherUser)
	h.registerAdmin(admin)

	h.disconnectFamilyUser("moved-user")

	if !wsClientClosed(first) || !wsClientClosed(second) {
		t.Fatal("moved user's family sockets were not closed")
	}
	if wsClientClosed(otherUser) {
		t.Fatal("other user's family socket was closed")
	}
	if wsClientClosed(admin) {
		t.Fatal("platform-admin socket was closed")
	}

	h.mu.Lock()
	defer h.mu.Unlock()
	if _, ok := h.familyUsers["moved-user"]; ok {
		t.Fatal("moved user remains in the family user index")
	}
	if _, ok := h.families["family-new"]; ok {
		t.Fatal("empty family socket set was not removed")
	}
	if _, ok := h.families["family-old"][otherUser]; !ok {
		t.Fatal("other user's family socket was removed from the hub")
	}
	if _, ok := h.admins[admin]; !ok {
		t.Fatal("platform-admin socket was removed from the hub")
	}
}

func testWSClient() *wsClient {
	return &wsClient{
		send: make(chan []byte, clientSendBuffer),
		done: make(chan struct{}),
	}
}

func wsClientClosed(c *wsClient) bool {
	select {
	case <-c.done:
		return true
	default:
		return false
	}
}
