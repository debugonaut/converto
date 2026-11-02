/**
 * Converto - Client-side device detection and theme management
 */

(function () {
  'use strict';

  function detectOS() {
    const userAgent = window.navigator.userAgent || '';
    const platform = window.navigator.platform || '';
    const macosPlatforms = ['Macintosh', 'MacIntel', 'MacPPC', 'Mac68K'];
    const windowsPlatforms = ['Win32', 'Win64', 'Windows', 'WinCE'];
    const iosPlatforms = ['iPhone', 'iPad', 'iPod'];

    if (macosPlatforms.indexOf(platform) !== -1 || /Mac OS X/.test(userAgent)) {
      return 'macos';
    } else if (iosPlatforms.indexOf(platform) !== -1 || (/Macintosh/.test(userAgent) && 'ontouchend' in document)) {
      return 'ios';
    } else if (windowsPlatforms.indexOf(platform) !== -1 || /Windows NT/.test(userAgent)) {
      return 'windows';
    } else if (/Android/.test(userAgent)) {
      return 'android';
    } else if (/Linux/.test(platform) || /Linux/.test(userAgent)) {
      return 'linux';
    }
    return 'macos';
  }

  function isAppleSilicon() {
    try {
      const canvas = document.createElement('canvas');
      const gl = canvas.getContext('webgl') || canvas.getContext('experimental-webgl');
      if (!gl) return true;
      const debugInfo = gl.getExtension('WEBGL_debug_renderer_info');
      if (debugInfo) {
        const renderer = gl.getParameter(debugInfo.UNMASKED_RENDERER_WEBGL);
        return /Apple/.test(renderer) && !/Intel/.test(renderer);
      }
    } catch (_) {}
    return true;
  }

  function setupDeviceDetection() {
    const os = detectOS();
    const deviceLabel = document.getElementById('deviceLabel');
    const primaryBtn = document.getElementById('primaryDownloadBtn');
    const primaryText = document.getElementById('primaryDownloadText');
    const downloadMeta = document.getElementById('downloadMeta');
    const appleSilicon = isAppleSilicon();

    const downloadProfiles = {
      macos: {
        name: 'macOS',
        buttonText: appleSilicon ? 'Download for macOS (Apple Silicon)' : 'Download for macOS (Intel)',
        url: appleSilicon
          ? 'downloads/Converto-macOS-arm64.zip'
          : 'downloads/Converto-macOS-x86_64.zip',
        meta: `Developer preview • ${appleSilicon ? '19.55' : '21.45'} MiB ZIP • macOS 13.0+`
      },
      windows: {
        name: 'Windows',
        buttonText: 'Download for Windows (x64)',
        url: 'downloads/Converto-Windows-x64.zip',
        meta: 'Developer preview • 24.12 MiB ZIP • Windows 10 & 11 (x64)'
      },
      linux: {
        name: 'Linux',
        buttonText: 'Download for Linux (x64)',
        url: 'downloads/Converto-Linux-x64.tar.gz',
        meta: 'Developer preview • 21.66 MiB tar.gz • GTK 3 • glibc 2.35+'
      },
      android: {
        name: 'Android',
        buttonText: 'Download Android APK',
        url: 'https://github.com/releases/download/v1.0.0/Converto-release.apk',
        meta: 'Standalone APK • Android 8.0+'
      },
      ios: {
        name: 'iOS / iPadOS',
        buttonText: 'Get on TestFlight',
        url: 'https://testflight.apple.com',
        meta: 'Offline vector conversion • iOS 15.0+'
      }
    };

    const profile = downloadProfiles[os] || downloadProfiles.macos;

    if (deviceLabel) deviceLabel.textContent = `Detected device: ${profile.name}`;
    if (primaryBtn) {
      primaryBtn.href = profile.url;
      if (os === 'macos' || os === 'windows' || os === 'linux') primaryBtn.download = profile.url.split('/').pop();
      else primaryBtn.removeAttribute('download');
    }
    if (primaryText) primaryText.textContent = profile.buttonText;
    if (downloadMeta) downloadMeta.textContent = profile.meta;

    // Highlight row in downloads list
    const activeRow = document.querySelector(`.download-row[data-os="${os}"]`);
    if (activeRow) {
      activeRow.classList.add('active-detected');
    }
  }

  function setupThemeToggle() {
    const toggleBtn = document.getElementById('themeToggle');
    const root = document.documentElement;

    function applyTheme(theme) {
      root.setAttribute('data-theme', theme);
      try {
        localStorage.setItem('oc_theme', theme);
      } catch (_) {}
    }

    const saved = localStorage.getItem('oc_theme');
    if (saved) {
      applyTheme(saved);
    }

    if (toggleBtn) {
      toggleBtn.addEventListener('click', () => {
        const current = root.getAttribute('data-theme') || 'dark';
        applyTheme(current === 'dark' ? 'light' : 'dark');
      });
    }
  }

  function setupCliTabs() {
    const tabs = document.querySelectorAll('.cli-tab');
    const cmdText = document.getElementById('cliCommandText');
    const copyBtn = document.getElementById('copyCmdBtn');
    const copyBtnText = document.getElementById('copyBtnText');

    tabs.forEach((tab) => {
      tab.addEventListener('click', () => {
        tabs.forEach((t) => t.classList.remove('active'));
        tab.classList.add('active');
        const cmd = tab.getAttribute('data-cmd');
        if (cmdText && cmd) {
          cmdText.textContent = cmd;
        }
      });
    });

    if (copyBtn && cmdText) {
      copyBtn.addEventListener('click', async () => {
        const textToCopy = cmdText.textContent || '';
        try {
          await navigator.clipboard.writeText(textToCopy);
          if (copyBtnText) copyBtnText.textContent = 'Copied!';
          setTimeout(() => {
            if (copyBtnText) copyBtnText.textContent = 'Copy';
          }, 2000);
        } catch (_) {
          const textarea = document.createElement('textarea');
          textarea.value = textToCopy;
          document.body.appendChild(textarea);
          textarea.select();
          document.execCommand('copy');
          document.body.removeChild(textarea);
          if (copyBtnText) copyBtnText.textContent = 'Copied!';
          setTimeout(() => {
            if (copyBtnText) copyBtnText.textContent = 'Copy';
          }, 2000);
        }
      });
    }
  }

  document.addEventListener('DOMContentLoaded', () => {
    setupDeviceDetection();
    setupThemeToggle();
    setupCliTabs();
  });
})();
