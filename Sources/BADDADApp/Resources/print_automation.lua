local appNames = hs.json.decode(os.getenv("BADDAD_APP_NAMES") or "[]") or {}
local key = os.getenv("BADDAD_KEY") or ""
local modifiers = hs.json.decode(os.getenv("BADDAD_MODIFIERS") or "[]") or {}

if key == "" then
    print("ERROR:Missing key")
    os.exit(3)
end

for _, name in ipairs(appNames) do
    local app = hs.application.find(name)
    if app then
        app:activate()
        hs.timer.usleep(600000)
        hs.eventtap.keyStroke(modifiers, key, 0, app)
        print("OK:" .. name)
        return
    end
end

print("ERROR:No target GTX application found")
os.exit(2)
