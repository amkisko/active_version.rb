module Layouts
  class DemoLayout < ApplicationComponent
    include StyleCapsule::Component

    style_capsule scoping_strategy: :nesting

    def initialize(current_user:, notice:, alert:, title: "ActiveVersion Demo")
      @current_user = current_user
      @notice = notice
      @alert = alert
      @title = title
    end

    def component_styles
      <<~CSS
        & {
          margin: 0;
          min-height: 100vh;
          font-family: "SF Pro Text", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
          line-height: 1.45;
        }

        .app-frame {
          --bg: #f3f6ff;
          --surface: rgba(255, 255, 255, 0.88);
          --surface-solid: #ffffff;
          --surface-alt: #f4f7ff;
          --border: #d7dff1;
          --text: #10162a;
          --muted: #5f6983;
          --brand: #0a66ff;
          --brand-strong: #0044c7;
          --danger: #b42318;
          --radius: 16px;
          --radius-sm: 12px;
          --shadow: 0 18px 40px rgba(14, 24, 47, 0.08);
          --focus: 0 0 0 3px rgba(10, 102, 255, 0.22);
          --nav-bg: #edf2ff;
          --nav-border: #d4e0ff;
          --nav-text: #26385f;
          --chip-bg: #f2f6ff;
          --chip-border: #d3ddf8;
          --chip-text: #32456b;
          --cli-bg: #10182a;
          --cli-border: #24304a;
          --cli-text: #dbe4ff;
          --blob-a: #c8dbff;
          --blob-b: #ffe0ef;
          --blob-c: #d8f6eb;
          min-height: 100vh;
          position: relative;
          overflow-x: clip;
          background: var(--bg);
          color: var(--text);
        }

        .app-frame[data-theme="dark"] {
          --bg: #090f1d;
          --surface: rgba(18, 27, 45, 0.82);
          --surface-solid: #16213a;
          --surface-alt: #1a2642;
          --border: #2a3a5f;
          --text: #e8eefc;
          --muted: #9aabcf;
          --brand: #6ea3ff;
          --brand-strong: #8db7ff;
          --nav-bg: #1a2746;
          --nav-border: #2d3f67;
          --nav-text: #d5e2ff;
          --chip-bg: #1b2848;
          --chip-border: #2c406d;
          --chip-text: #d6e3ff;
          --cli-bg: #0f172a;
          --cli-border: #334266;
          --cli-text: #e4ecff;
          --blob-a: #173f90;
          --blob-b: #5c2a63;
          --blob-c: #1d5b4a;
          --shadow: 0 18px 40px rgba(0, 0, 0, 0.4);
        }

        .app-frame[data-theme="leary"] {
          --bg: #fef7f1;
          --surface: rgba(255, 252, 246, 0.9);
          --surface-solid: #fffaf3;
          --surface-alt: #fff5ea;
          --border: #ecd9c8;
          --text: #2d1f16;
          --muted: #856a58;
          --brand: #ff6b4a;
          --brand-strong: #d9482f;
          --nav-bg: #ffe9dd;
          --nav-border: #f7ccb9;
          --nav-text: #6b2f22;
          --chip-bg: #ffeede;
          --chip-border: #f6d0b9;
          --chip-text: #74352b;
          --cli-bg: #311c18;
          --cli-border: #5a3832;
          --cli-text: #ffe9dc;
          --blob-a: #ffd6bb;
          --blob-b: #ffbfde;
          --blob-c: #ffe8a8;
        }

        .app-frame[data-theme="neon"] {
          --bg: #060810;
          --surface: rgba(18, 16, 36, 0.82);
          --surface-solid: #17142f;
          --surface-alt: #1f1a40;
          --border: #413d74;
          --text: #f3f5ff;
          --muted: #b4b9e6;
          --brand: #14f1d9;
          --brand-strong: #76fff0;
          --nav-bg: #242050;
          --nav-border: #4f4a96;
          --nav-text: #d6d9ff;
          --chip-bg: #222058;
          --chip-border: #4a4692;
          --chip-text: #d6dbff;
          --cli-bg: #0a0f24;
          --cli-border: #354078;
          --cli-text: #d5e2ff;
          --blob-a: #2f6eff;
          --blob-b: #b13dff;
          --blob-c: #00c3a6;
          --shadow: 0 22px 56px rgba(0, 0, 0, 0.56);
        }

        .app-frame[data-theme="forest"] {
          --bg: #eef5ef;
          --surface: rgba(252, 255, 252, 0.88);
          --surface-solid: #fbfffb;
          --surface-alt: #f1f8f0;
          --border: #cfe2d0;
          --text: #0f2618;
          --muted: #4f6b59;
          --brand: #2c8a5e;
          --brand-strong: #206f4b;
          --nav-bg: #e4f3e7;
          --nav-border: #c6e2ce;
          --nav-text: #24513a;
          --chip-bg: #e8f5e9;
          --chip-border: #c8e0c9;
          --chip-text: #29543e;
          --cli-bg: #11291b;
          --cli-border: #2c4e39;
          --cli-text: #d8f0df;
          --blob-a: #cdeece;
          --blob-b: #bee0cb;
          --blob-c: #d9f0c7;
        }

        .liquid-bg {
          position: fixed;
          inset: 0;
          pointer-events: none;
          z-index: 0;
          overflow: hidden;
        }
        .liquid-blob {
          position: absolute;
          filter: blur(56px);
          opacity: 0.6;
          border-radius: 999px;
          transform: translate3d(0, 0, 0);
          animation: drift 16s ease-in-out infinite alternate;
        }
        .liquid-blob.a { width: 42vw; height: 42vw; left: -10vw; top: -12vw; background: var(--blob-a); }
        .liquid-blob.b { width: 34vw; height: 34vw; right: -6vw; top: 12vh; background: var(--blob-b); animation-duration: 20s; }
        .liquid-blob.c { width: 36vw; height: 36vw; left: 24vw; bottom: -18vw; background: var(--blob-c); animation-duration: 22s; }
        @keyframes drift {
          0% { transform: translate3d(0, 0, 0) scale(1); }
          100% { transform: translate3d(0, -20px, 0) scale(1.08); }
        }

        .shell {
          max-width: 1140px;
          margin: 0 auto;
          padding: 18px 18px 96px;
          display: grid;
          gap: 14px;
          position: relative;
          z-index: 1;
        }

        .topbar {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 10px;
          background: var(--surface);
          border: 1px solid var(--border);
          border-radius: 999px;
          padding: 10px 12px;
          box-shadow: var(--shadow);
          backdrop-filter: blur(12px);
          position: sticky;
          top: 10px;
          z-index: 20;
        }

        .brand {
          font-weight: 780;
          font-size: 1.06rem;
          letter-spacing: -0.01em;
          padding: 0 8px;
          white-space: nowrap;
        }

        .nav {
          display: flex;
          gap: 6px;
          flex-wrap: nowrap;
          overflow-x: auto;
          scrollbar-width: none;
          -ms-overflow-style: none;
        }
        .nav::-webkit-scrollbar { display: none; }
        .nav a {
          text-decoration: none;
          color: var(--nav-text);
          background: var(--nav-bg);
          border: 1px solid var(--nav-border);
          border-radius: 999px;
          padding: 6px 11px;
          font-size: 0.84rem;
          font-weight: 600;
          transition: background-color 120ms ease, color 120ms ease, border-color 120ms ease;
          white-space: nowrap;
        }
        .nav a:hover {
          color: var(--brand-strong);
          border-color: color-mix(in srgb, var(--brand) 45%, var(--nav-border));
          background: color-mix(in srgb, var(--brand) 20%, var(--nav-bg));
        }
        .nav a[aria-current="page"] {
          background: var(--brand);
          color: #fff;
          border-color: var(--brand);
        }

        .flash {
          border-radius: var(--radius-sm);
          padding: 10px 13px;
          border: 1px solid var(--border);
          background: var(--surface-solid);
          font-size: 0.92rem;
        }

        .flash.alert { border-color: #f2c9c5; background: #fff2f0; color: var(--danger); }

        .card {
          background: var(--surface);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          box-shadow: var(--shadow);
          padding: 16px 18px;
          backdrop-filter: blur(10px);
        }

        .card h1, .card h2 {
          margin-top: 0;
          margin-bottom: 8px;
          letter-spacing: -0.02em;
        }
        .card h1 {
          font-size: clamp(1.5rem, 2vw, 2rem);
          font-weight: 760;
        }
        .card h2 {
          font-size: clamp(1.14rem, 1.5vw, 1.4rem);
          font-weight: 710;
        }
        .muted { color: var(--muted); font-size: 0.95rem; }

        .feed-layout {
          display: grid;
          grid-template-columns: minmax(0, 1.6fr) minmax(0, 1fr);
          gap: 14px;
          align-items: start;
        }
        .stack { display: grid; gap: 12px; }

        .kicker {
          text-transform: uppercase;
          letter-spacing: 0.08em;
          font-size: 0.71rem;
          font-weight: 700;
          color: var(--brand-strong);
          margin-bottom: 8px;
        }

        .chip-list { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 10px; }
        .chip {
          border: 1px solid var(--chip-border);
          border-radius: 999px;
          background: var(--chip-bg);
          color: var(--chip-text);
          font-size: 0.78rem;
          font-weight: 600;
          padding: 4px 10px;
        }

        .timeline {
          list-style: none;
          margin: 0;
          padding: 0;
          display: grid;
          gap: 10px;
        }
        .timeline-item {
          border: 1px solid var(--border);
          border-radius: var(--radius-sm);
          background: var(--surface-alt);
          padding: 12px 13px;
          display: grid;
          gap: 6px;
        }
        .timeline-item-title a {
          text-decoration: none;
          font-weight: 680;
          color: var(--text);
        }
        .timeline-item-title a:hover { color: var(--brand-strong); }
        .timeline-item-meta {
          color: var(--muted);
          font-size: 0.79rem;
          display: flex;
          flex-wrap: wrap;
          gap: 8px;
        }
        .timeline-item-actions a {
          font-size: 0.8rem;
          text-decoration: none;
          color: var(--brand-strong);
          margin-right: 9px;
        }

        table {
          width: 100%;
          border-collapse: separate;
          border-spacing: 0;
          font-size: 0.88rem;
          border: 1px solid var(--border);
          border-radius: 12px;
          overflow: hidden;
        }

        th, td {
          text-align: left;
          padding: 9px 10px;
          border-bottom: 1px solid var(--border);
          vertical-align: top;
        }

        thead th {
          background: var(--surface-alt);
          color: #5b6783;
          font-size: 0.72rem;
          text-transform: uppercase;
          letter-spacing: 0.08em;
          font-weight: 700;
        }

        tbody tr:nth-child(even) { background: #fafcff; }
        tbody tr:hover { background: #f2f7ff; }
        tbody tr:last-child td { border-bottom: none; }

        .grid {
          display: grid;
          gap: 12px;
          grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
        }

        .field { margin-bottom: 11px; }
        .field label {
          display: block;
          font-size: 0.74rem;
          text-transform: uppercase;
          color: var(--muted);
          margin-bottom: 5px;
          letter-spacing: 0.07em;
          font-weight: 650;
        }

        .field input, .field textarea, .field select {
          width: 100%;
          border: 1px solid var(--border);
          border-radius: 11px;
          background: #fff;
          color: var(--text);
          padding: 9px 11px;
          font: inherit;
          font-size: 0.92rem;
          transition: border-color 120ms ease, box-shadow 120ms ease, background-color 120ms ease;
        }
        .field input:focus, .field textarea:focus, .field select:focus {
          border-color: #a9c2ff;
          box-shadow: var(--focus);
          outline: none;
          background: #fff;
        }

        .actions {
          display: flex;
          gap: 8px;
          flex-wrap: wrap;
          margin-top: 10px;
          align-items: center;
        }
        .btn, button, input[type="submit"] {
          border-radius: 999px;
          border: 1px solid #c8d7fd;
          background: #ecf2ff;
          color: #20427f;
          padding: 7px 12px;
          text-decoration: none;
          font-size: 0.86rem;
          font-weight: 650;
          cursor: pointer;
          line-height: 1.2;
          transition: border-color 120ms ease, background-color 120ms ease, color 120ms ease;
        }
        .btn:hover, button:hover, input[type="submit"]:hover {
          border-color: #b3c9ff;
          background: #dfeaff;
          color: var(--brand-strong);
        }
        .btn.primary, input[type="submit"] { background: var(--brand); color: #fff; border-color: var(--brand); }
        .btn.primary:hover, input[type="submit"]:hover { background: var(--brand-strong); border-color: var(--brand-strong); color: #fff; }
        .btn.danger { background: #fff2f0; color: var(--danger); border-color: #f2c9c5; }

        .cli-shell {
          position: fixed;
          left: 0;
          right: 0;
          bottom: 0;
          z-index: 40;
          padding: 8px 12px calc(env(safe-area-inset-bottom, 0px) + 8px);
        }

        .cli-wrap {
          max-width: 1140px;
          margin: 0 auto;
          display: grid;
          gap: 6px;
        }

        .cli-output {
          background: color-mix(in srgb, var(--cli-bg) 92%, black);
          color: var(--cli-text);
          border: 1px solid var(--cli-border);
          border-radius: 12px;
          padding: 8px 10px;
          max-height: 220px;
          overflow: auto;
          font-size: 0.84rem;
        }

        .cli-title { font-weight: 700; margin-bottom: 6px; }
        .cli-line a { color: color-mix(in srgb, var(--brand) 55%, #9cc2ff); }

        .cli-bar {
          display: grid;
          grid-template-columns: 26px 1fr;
          align-items: center;
          background: var(--cli-bg);
          color: var(--cli-text);
          border: 1px solid var(--cli-border);
          border-radius: 12px;
          padding: 3px 8px;
        }
        .cli-input {
          border: none;
          background: transparent;
          color: inherit;
          font: inherit;
          outline: none;
          padding: 8px 2px;
        }
        .cli-prefix { color: #88a9e0; text-align: center; }

        .topbar-right {
          display: flex;
          align-items: center;
          gap: 8px;
          padding-right: 4px;
        }
        .theme-picker {
          appearance: none;
          border: 1px solid var(--border);
          border-radius: 999px;
          background: var(--surface-solid);
          color: var(--text);
          font: inherit;
          font-size: 0.78rem;
          padding: 6px 26px 6px 10px;
          line-height: 1.2;
        }
        .theme-picker:focus { outline: none; box-shadow: var(--focus); }

        @media (max-width: 820px) {
          .shell { padding: 12px 12px 96px; }
          .topbar {
            position: static;
            border-radius: 14px;
            display: grid;
            gap: 8px;
            justify-content: stretch;
          }
          .brand { font-size: 0.98rem; }
          .topbar-right { justify-content: flex-end; }
          .feed-layout { grid-template-columns: 1fr; }
          .card { padding: 14px; }
          table { font-size: 0.82rem; }
          th, td { padding: 8px 8px; }
        }
      CSS
    end

    def view_template
      doctype
      html(lang: "en") do
        head do
          meta(charset: "utf-8")
          meta(name: "viewport", content: "width=device-width, initial-scale=1, viewport-fit=cover")
          title { @title }
          raw_html helpers.csrf_meta_tags
          raw_html helpers.csp_meta_tag
          raw_html helpers.javascript_importmap_tags
        end

        body do
          div(id: "av-app", class: "app-frame", data: { theme: "light" }) do
            div(class: "liquid-bg", aria: { hidden: true }) do
              div(class: "liquid-blob a")
              div(class: "liquid-blob b")
              div(class: "liquid-blob c")
            end

            div(class: "shell") do
              topbar
              flash_messages
              yield
            end

            command_line_shell
          end

          command_line_script
        end
      end
    end

    private

    def topbar
      header(class: "topbar") do
        div(class: "brand") { "ActiveVersion Demo" }
        nav(class: "nav") do
          nav_link("Home", helpers.root_path)
          nav_link("Posts", helpers.posts_path)
          nav_link("Issues", helpers.issues_path)
          nav_link("Pull Requests", helpers.pull_requests_path)
          nav_link("Categories", helpers.categories_path)
          nav_link("Profile", helpers.user_path(@current_user)) if @current_user
          nav_link("Admin", "/admin")
        end
        div(class: "topbar-right") do
          label(for: "theme-picker", class: "muted") { "Theme" }
          select(id: "theme-picker", class: "theme-picker", aria: { label: "Theme picker" }) do
            option(value: "light") { "Light" }
            option(value: "dark") { "Dark" }
            option(value: "leary") { "Leary" }
            option(value: "neon") { "Neon" }
            option(value: "forest") { "Forest" }
          end
        end
      end
    end

    def nav_link(label, path)
      options = {}
      options[:aria] = { current: "page" } if helpers.current_page?(path)
      raw_html helpers.link_to(label, path, options)
    end

    def flash_messages
      div(class: "flash notice") { @notice } if @notice.present?
      div(class: "flash alert") { @alert } if @alert.present?
    end

    def command_line_shell
      section(class: "cli-shell", aria: { label: "Command line" }) do
        div(class: "cli-wrap") do
          div(id: "av-cli-output", class: "cli-output", hidden: true)
          form(id: "av-cli-form", class: "cli-bar") do
            span(class: "cli-prefix") { ":" }
            input(
              id: "av-cli-input",
              class: "cli-input",
              type: "text",
              autocomplete: "off",
              spellcheck: "false",
              placeholder: "help | search test | post create | create post",
              aria: { label: "Command line" }
            )
          end
        end
      end
    end

    def command_line_script
      script do
        raw_html <<~JS
          (() => {
            const form = document.getElementById("av-cli-form");
            const input = document.getElementById("av-cli-input");
            const output = document.getElementById("av-cli-output");
            const appRoot = document.getElementById("av-app");
            const themePicker = document.getElementById("theme-picker");
            if (!form || !input || !output || !appRoot || !themePicker) return;

            const themes = ["light", "dark", "leary", "neon", "forest"];
            const storedTheme = localStorage.getItem("av_theme");
            const fallbackTheme = window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
            const initialTheme = themes.includes(storedTheme) ? storedTheme : fallbackTheme;

            const applyTheme = (theme) => {
              if (!themes.includes(theme)) return;
              appRoot.dataset.theme = theme;
              themePicker.value = theme;
              localStorage.setItem("av_theme", theme);
            };

            applyTheme(initialTheme);
            themePicker.addEventListener("change", () => applyTheme(themePicker.value));

            const tokenMeta = document.querySelector("meta[name='csrf-token']");
            const csrfToken = tokenMeta ? tokenMeta.content : "";
            const history = [];
            let historyIndex = -1;

            const renderResult = (result) => {
              output.innerHTML = "";
              const title = document.createElement("div");
              title.className = "cli-title";
              title.textContent = result.title || "Result";
              output.appendChild(title);

              const lineItems = result.line_items || result.lines || [];
              lineItems.forEach((line) => {
                const row = document.createElement("div");
                row.className = "cli-line";
                if (line && typeof line === "object") {
                  const text = line.text || line.title || line.label || JSON.stringify(line);
                  const href = line.href || line.url;
                  if (href) {
                    const link = document.createElement("a");
                    link.href = href;
                    link.textContent = text;
                    row.appendChild(link);
                  } else {
                    row.textContent = text;
                  }
                } else {
                  row.textContent = String(line);
                }
                output.appendChild(row);
              });
              output.hidden = false;
              output.scrollTop = 0;
            };

            const pushHistory = (command) => {
              if (!command) return;
              if (history[history.length - 1] !== command) history.push(command);
              historyIndex = history.length;
            };

            const setHistoryValue = (direction) => {
              if (!history.length) return;
              historyIndex = Math.max(0, Math.min(history.length, historyIndex + direction));
              if (historyIndex === history.length) {
                input.value = "";
                return;
              }
              input.value = history[historyIndex];
            };

            input.addEventListener("keydown", (event) => {
              if (event.key === "ArrowUp") {
                event.preventDefault();
                setHistoryValue(-1);
              }
              if (event.key === "ArrowDown") {
                event.preventDefault();
                setHistoryValue(1);
              }
            });

            form.addEventListener("submit", async (event) => {
              event.preventDefault();
              const command = input.value.trim();
              if (!command) return;
              pushHistory(command);

              try {
                const response = await fetch("/command_line", {
                  method: "POST",
                  headers: {
                    "Content-Type": "application/json",
                    "Accept": "application/json",
                    "X-CSRF-Token": csrfToken
                  },
                  body: JSON.stringify({ command })
                });

                const result = await response.json();
                renderResult(result);
              } catch (error) {
                renderResult({ title: "Command Error", lines: [String(error)] });
              }

              input.value = "";
            });
          })();
        JS
      end
    end
  end
end
