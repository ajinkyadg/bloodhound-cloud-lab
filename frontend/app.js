// Config is injected by scripts/deploy.sh into config.js (not committed) from
// `terraform output`. See config.example.js for the shape.
const { API_BASE, COGNITO_DOMAIN, CLIENT_ID } = window.BLOODHOUND_CONFIG;

const redirectUri = window.location.origin + "/";

const el = (id) => document.getElementById(id);

function loginUrl() {
  const params = new URLSearchParams({
    client_id: CLIENT_ID,
    response_type: "token",
    scope: "openid email",
    redirect_uri: redirectUri,
  });
  return `${COGNITO_DOMAIN}/login?${params.toString()}`;
}

function logoutUrl() {
  const params = new URLSearchParams({
    client_id: CLIENT_ID,
    logout_uri: redirectUri,
  });
  return `${COGNITO_DOMAIN}/logout?${params.toString()}`;
}

function extractTokenFromFragment() {
  if (!window.location.hash) return null;
  const params = new URLSearchParams(window.location.hash.slice(1));
  const idToken = params.get("id_token");
  if (idToken) {
    history.replaceState(null, "", window.location.pathname);
    return idToken;
  }
  return null;
}

function getToken() {
  const fromFragment = extractTokenFromFragment();
  if (fromFragment) {
    sessionStorage.setItem("id_token", fromFragment);
    return fromFragment;
  }
  return sessionStorage.getItem("id_token");
}

async function apiCall(path, method = "GET") {
  const token = getToken();
  const res = await fetch(`${API_BASE}${path}`, {
    method,
    headers: { Authorization: `Bearer ${token}` },
  });
  if (res.status === 401 || res.status === 403) {
    sessionStorage.removeItem("id_token");
    showLoggedOut();
    throw new Error("session expired");
  }
  return res.json();
}

let pollTimer = null;
let heartbeatTimer = null;

function showLoggedOut() {
  el("logged-out").hidden = false;
  el("logged-in").hidden = true;
  clearInterval(pollTimer);
  clearInterval(heartbeatTimer);
}

function showLoggedIn() {
  el("logged-out").hidden = true;
  el("logged-in").hidden = false;
}

async function refreshStatus() {
  const status = await apiCall("/status");
  el("state-text").textContent = `Instance: ${status.state}`;

  el("launch-btn").hidden = status.state === "running";
  el("launch-btn").disabled = status.state === "pending";
  el("open-link").hidden = !status.ready;
  el("creds-btn").hidden = !status.ready;
  el("stop-btn").hidden = status.state === "stopped";

  if (status.ready) {
    el("open-link").href = status.url;
    el("state-text").textContent = "BloodHound is ready.";
    clearInterval(pollTimer); // stop polling /status once up; heartbeat keeps the session alive
    startHeartbeat();
  }
  return status;
}

function startPolling() {
  clearInterval(pollTimer);
  pollTimer = setInterval(() => refreshStatus().catch(() => {}), 5000);
}

function startHeartbeat() {
  if (heartbeatTimer) return;
  heartbeatTimer = setInterval(() => apiCall("/heartbeat", "POST").catch(() => {}), 60000);
}

el("login-btn").addEventListener("click", () => {
  window.location.href = loginUrl();
});

el("launch-btn").addEventListener("click", async () => {
  el("launch-btn").disabled = true;
  el("state-text").textContent = "Starting instance…";
  await apiCall("/launch", "POST");
  startPolling();
});

el("creds-btn").addEventListener("click", async () => {
  el("creds-btn").disabled = true;
  el("creds-btn").textContent = "Fetching…";
  el("creds-output").hidden = false;
  el("creds-output").textContent = "Asking the instance for its BloodHound admin credentials (a few seconds)…";
  try {
    const { output, error } = await apiCall("/credentials");
    el("creds-output").textContent = output || error || "No response.";
  } catch (e) {
    el("creds-output").textContent = "Failed to fetch credentials: " + e.message;
  } finally {
    el("creds-btn").disabled = false;
    el("creds-btn").textContent = "Show BloodHound credentials";
  }
});

el("stop-btn").addEventListener("click", async () => {
  await apiCall("/stop", "POST");
  sessionStorage.removeItem("id_token");
  window.location.href = logoutUrl();
});

(async function init() {
  const token = getToken();
  if (!token) {
    showLoggedOut();
    return;
  }
  showLoggedIn();
  try {
    await refreshStatus();
    startPolling();
  } catch (e) {
    // refreshStatus already handles 401/403 by showing the login screen
  }
})();
