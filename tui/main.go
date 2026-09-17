// stardust-tui — Bubble Tea front-end over the Stardust CLI.
// Does not reimplement backup/upgrade. Do not run as root.
package main

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/charmbracelet/bubbles/list"
	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

var stardustBin = "stardust"

type item struct {
	title, desc string
	run         func(m model) tea.Cmd
}

func (i item) Title() string       { return i.title }
func (i item) Description() string { return i.desc }
func (i item) FilterValue() string { return i.title }

type siteItem struct {
	plat, prod string
}

func (s siteItem) Title() string       { return s.plat + "/" + s.prod }
func (s siteItem) Description() string { return "product" }
func (s siteItem) FilterValue() string { return s.plat + "/" + s.prod }

type platItem struct{ name string }

func (p platItem) Title() string       { return p.name }
func (p platItem) Description() string { return "platform" }
func (p platItem) FilterValue() string { return p.name }

type screen int

const (
	screenMenu screen = iota
	screenSites
	screenPlats
	screenOut
)

type doneMsg struct {
	out string
	err error
}

type model struct {
	screen   screen
	menu     list.Model
	sites    list.Model
	plats    list.Model
	vp       viewport.Model
	spin     spinner.Model
	busy     bool
	status   string
	pending  string // site-check, site-backup, ...
	width    int
	height   int
}

func runSD(args ...string) tea.Cmd {
	return func() tea.Msg {
		cmd := exec.Command(stardustBin, args...)
		var buf bytes.Buffer
		cmd.Stdout = &buf
		cmd.Stderr = &buf
		err := cmd.Run()
		return doneMsg{out: buf.String(), err: err}
	}
}

func parseSites(out string) []list.Item {
	var items []list.Item
	for _, line := range strings.Split(out, "\n") {
		if !strings.HasPrefix(line, "platform=") {
			continue
		}
		plat, prod := "", ""
		for _, f := range strings.Fields(line) {
			k, v, ok := strings.Cut(f, "=")
			if !ok {
				continue
			}
			switch k {
			case "platform":
				plat = v
			case "product":
				prod = v
			}
		}
		if plat != "" && prod != "" {
			items = append(items, siteItem{plat: plat, prod: prod})
		}
	}
	return items
}

func parsePlats(out string) []list.Item {
	seen := map[string]bool{}
	var items []list.Item
	for _, line := range strings.Split(out, "\n") {
		if !strings.HasPrefix(line, "platform=") {
			continue
		}
		for _, f := range strings.Fields(line) {
			k, v, ok := strings.Cut(f, "=")
			if ok && k == "platform" && !seen[v] {
				seen[v] = true
				items = append(items, platItem{name: v})
			}
		}
	}
	return items
}

func newModel() model {
	delegate := list.NewDefaultDelegate()
	actions := []list.Item{
		item{"doctor", "host health", func(m model) tea.Cmd { return runSD("doctor") }},
		item{"list", "platforms on disk", func(m model) tea.Cmd { return runSD("list") }},
		item{"inventory", "platform product branch backup", func(m model) tea.Cmd { return runSD("inventory") }},
		item{"log", "last 20 tasks", func(m model) tea.Cmd { return runSD("log", "20") }},
		item{"last", "last task line", func(m model) tea.Cmd { return runSD("last") }},
		item{"site-check", "smoke-test one product", nil},
		item{"site-backup", "backup one product", nil},
		item{"site-restore", "restore latest backup", nil},
		item{"site-disable", "maintenance on", nil},
		item{"site-enable", "maintenance off", nil},
		item{"platform-upgrade", "backup + pull + updb + check", nil},
		item{"promote-test", "ff-only origin/test then upgrade", func(m model) tea.Cmd { return runSD("promote", "ecom", "--to", "test") }},
		item{"promote-live", "ff-only origin/live then upgrade", func(m model) tea.Cmd { return runSD("promote", "ecom", "--to", "live") }},
		item{"backup-all", "every product, prune KEEP_BACKUPS", func(m model) tea.Cmd { return runSD("backup-all") }},
		item{"quit", "return to the shell", nil},
	}
	menu := list.New(actions, delegate, 40, 16)
	menu.Title = "Stardust"
	menu.SetShowStatusBar(false)
	menu.SetFilteringEnabled(true)

	sp := spinner.New()
	sp.Spinner = spinner.Line
	sp.Style = lipgloss.NewStyle().Foreground(lipgloss.Color("212"))

	return model{
		screen: screenMenu,
		menu:   menu,
		spin:   sp,
		status: "q quit  enter run  / filter   wraps " + stardustBin,
	}
}

func (m model) Init() tea.Cmd { return m.spin.Tick }

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		h := msg.Height - 4
		if h < 8 {
			h = 8
		}
		m.menu.SetSize(msg.Width-2, h)
		m.vp.Width = msg.Width - 2
		m.vp.Height = h
		if m.sites.Items() != nil {
			m.sites.SetSize(msg.Width-2, h)
		}
		if m.plats.Items() != nil {
			m.plats.SetSize(msg.Width-2, h)
		}
		return m, nil

	case spinner.TickMsg:
		var cmd tea.Cmd
		m.spin, cmd = m.spin.Update(msg)
		return m, cmd

	case doneMsg:
		m.busy = false
		body := msg.out
		if msg.err != nil {
			body += fmt.Sprintf("\n\nexit: %v", msg.err)
			m.status = "FAIL  esc back"
		} else {
			m.status = "OK  esc back"
		}
		if body == "" {
			body = "(no output)"
		}
		m.vp.SetContent(body)
		m.screen = screenOut
		return m, nil

	case tea.KeyMsg:
		if m.busy {
			return m, nil
		}
		switch msg.String() {
		case "ctrl+c":
			return m, tea.Quit
		case "esc":
			if m.screen != screenMenu {
				m.screen = screenMenu
				m.status = "q quit  enter run  / filter"
				return m, nil
			}
		case "q":
			if m.screen == screenMenu && !m.menu.SettingFilter() {
				return m, tea.Quit
			}
			if m.screen == screenOut {
				m.screen = screenMenu
				return m, nil
			}
		case "enter":
			return m.onEnter()
		}
	}

	var cmd tea.Cmd
	switch m.screen {
	case screenMenu:
		m.menu, cmd = m.menu.Update(msg)
	case screenSites:
		m.sites, cmd = m.sites.Update(msg)
	case screenPlats:
		m.plats, cmd = m.plats.Update(msg)
	case screenOut:
		m.vp, cmd = m.vp.Update(msg)
	}
	return m, cmd
}

func (m model) onEnter() (tea.Model, tea.Cmd) {
	switch m.screen {
	case screenOut:
		m.screen = screenMenu
		return m, nil
	case screenSites:
		it, ok := m.sites.SelectedItem().(siteItem)
		if !ok {
			return m, nil
		}
		m.busy = true
		m.status = m.spin.View() + " " + m.pending + " " + it.plat + "/" + it.prod
		m.screen = screenMenu
		return m, tea.Batch(m.spin.Tick, runSD(m.pending, it.plat, it.prod))
	case screenPlats:
		it, ok := m.plats.SelectedItem().(platItem)
		if !ok {
			return m, nil
		}
		m.busy = true
		m.status = m.spin.View() + " platform-upgrade " + it.name
		m.screen = screenMenu
		return m, tea.Batch(m.spin.Tick, runSD("platform-upgrade", it.name))
	case screenMenu:
		it, ok := m.menu.SelectedItem().(item)
		if !ok {
			return m, nil
		}
		switch it.title {
		case "quit":
			return m, tea.Quit
		case "site-check", "site-backup", "site-restore", "site-disable", "site-enable":
			return m.loadSites(it.title)
		case "platform-upgrade":
			return m.loadPlats()
		default:
			if it.run == nil {
				return m, nil
			}
			m.busy = true
			m.status = m.spin.View() + " " + it.title
			return m, tea.Batch(m.spin.Tick, it.run(m))
		}
	}
	return m, nil
}

func (m model) loadSites(verb string) (tea.Model, tea.Cmd) {
	out, err := exec.Command(stardustBin, "inventory").CombinedOutput()
	if err != nil {
		m.vp.SetContent(string(out) + "\n" + err.Error())
		m.screen = screenOut
		m.status = "inventory failed  esc back"
		return m, nil
	}
	items := parseSites(string(out))
	if len(items) == 0 {
		m.vp.SetContent("inventory empty — add a site first")
		m.screen = screenOut
		return m, nil
	}
	m.pending = verb
	m.sites = list.New(items, list.NewDefaultDelegate(), m.menu.Width(), m.menu.Height())
	m.sites.Title = verb + " — pick product"
	m.screen = screenSites
	m.status = "enter run  esc back"
	return m, nil
}

func (m model) loadPlats() (tea.Model, tea.Cmd) {
	out, err := exec.Command(stardustBin, "inventory").CombinedOutput()
	if err != nil {
		m.vp.SetContent(string(out) + "\n" + err.Error())
		m.screen = screenOut
		return m, nil
	}
	items := parsePlats(string(out))
	if len(items) == 0 {
		m.vp.SetContent("no platforms")
		m.screen = screenOut
		return m, nil
	}
	m.plats = list.New(items, list.NewDefaultDelegate(), m.menu.Width(), m.menu.Height())
	m.plats.Title = "platform-upgrade"
	m.screen = screenPlats
	m.status = "enter run  esc back"
	return m, nil
}

var (
	frame = lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).BorderForeground(lipgloss.Color("63"))
	foot  = lipgloss.NewStyle().Foreground(lipgloss.Color("245"))
)

func (m model) View() string {
	var body string
	switch m.screen {
	case screenMenu:
		body = m.menu.View()
	case screenSites:
		body = m.sites.View()
	case screenPlats:
		body = m.plats.View()
	case screenOut:
		body = m.vp.View()
	}
	head := "stardust-tui  (Bubble Tea over " + stardustBin + ")"
	if m.busy {
		head = m.spin.View() + " " + head
	}
	return frame.Render(head+"\n"+body) + "\n" + foot.Render(m.status)
}

func main() {
	if os.Geteuid() == 0 || os.Getenv("SUDO_USER") != "" {
		fmt.Fprintln(os.Stderr, "stardust-tui: do not run this with sudo or as root.")
		fmt.Fprintln(os.Stderr, "stardust-tui: log in as your operator account and run: stardust-tui")
		os.Exit(2)
	}
	if v := os.Getenv("STARDUST_BIN"); v != "" {
		stardustBin = v
	}
	if _, err := exec.LookPath(stardustBin); err != nil {
		fmt.Fprintf(os.Stderr, "stardust-tui: %s not on PATH\n", stardustBin)
		os.Exit(1)
	}
	p := tea.NewProgram(newModel(), tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
