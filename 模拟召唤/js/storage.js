const STORAGE_KEY = "hex-summoning-circle:v1";

export const CircleStorage = Object.freeze({
  save(payload) {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(payload));
    return new Date();
  },
  load() {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      return raw ? JSON.parse(raw) : null;
    } catch {
      return null;
    }
  },
});
