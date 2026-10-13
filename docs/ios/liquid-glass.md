# Liquid Glass for «Роутер»: design and code guide (stage 4)

> **Справочный документ (этап 4, 13.10.2026).** Как приложение оформлено в стиле Liquid Glass (iOS 26) и что показывать на iOS 17–25.
> Собран по документации Apple (developer.apple.com, HIG) на 13.10.2026. Реализация — `ios/Router/Components/GlassKit.swift`;
> правила экранов — `docs/ios/contract-stage4.md` §8. **При расхождении прав код приложения**, а данные и тексты — по коду
> сервера (`server/auth/*.php`), CGI роутера и `web/app.js`. «contract §6» в примерах кода — `docs/ios/contract-stage3.md` §6.
> HTML-макеты, на которые ссылается §3.12, в репозиторий не входят.
>
> *Reference (stage 4, 13.10.2026): Liquid Glass design and code guide, from Apple documentation. The app code
> (`ios/Router/Components/GlassKit.swift`) and the server code win on any disagreement.*

13.10.2026. Written for the stage 4 coding agents. The owner wants the app to look «плюс-минус в стиле Liquid Glass» (iOS 26). The owner's phone is an iPhone 17 Pro on iOS 26.x. The app's deployment target stays **iOS 17.0**. It is built with Xcode 26.x and the iOS 26 SDK in Swift 5 mode, so every iOS 26 API compiles but must sit behind `if #available(iOS 26.0, *)`.

Sources: Apple doc JSON fetched today from `https://developer.apple.com/tutorials/data/documentation/swiftui/<symbol>.json`. The human-readable page is the same path under `https://developer.apple.com/documentation/swiftui/…`. The HIG pages and the "Adopting Liquid Glass" overview were fetched the same way.

> **Note on the docs.** Apple's live docs already show the next SDK. Some declarations are spelled `@ContentBuilder` (a new `typealias ContentBuilder = ViewBuilder`) or carry `@export(implementation)`. Call sites look the same either way. Every availability below was read from the `platforms` field. Anything marked **26.1** needs `#available(iOS 26.1, *)`. Nothing here needs iOS 27.

---

## 0. TL;DR

1. **Let the system do the glass.** On iOS 26 the TabView tab bar, navigation bar, toolbar items, sheets, menus, alerts, segmented pickers, toggles and sliders all become Liquid Glass when built with SDK 26. Don't paint backgrounds on them: no `toolbarBackground`, no `UITabBar.appearance()`, no `presentationBackground` on iOS 26.
2. **Two layers.** The *control layer* is glass: tab bar, toolbar, buttons, filter chips, floating toast or status pill. The *content layer* is a soft tinted gradient plus **material** cards (`Material.regular`) with a thin light rim. This follows the HIG rule "Don't use Liquid Glass in the content layer". The result reads as glass but keeps dense numbers legible.
3. **At most one hero glass card per screen.** An example is the verdict on «Сводка», drawn with `glassEffect(.regular.tint(tone), in: .rect)`.
4. **Buttons** use `.buttonStyle(.glassProminent)` with a tint for primary (green) and destructive-fill (red), and `.buttonStyle(.glass)` for secondary and destructive-outline (red label). On iOS < 26 they fall back to the existing `ActionButtonStyle`.
5. **Chips and filters**: put interactive glass capsules inside one `GlassEffectContainer`. Use a segmented `Picker` (system glass) for 2–4 fixed options.
6. **Numbers** use `.monospacedDigit()`, never `design: .monospaced`. Use `.contentTransition(.numericText())` for live values.
7. **App switcher**: data shows by default. The cover becomes the Settings toggle «Скрывать в переключателе приложений» (default off). Watch out for the "Сразу" lock, see §5.12.

---

## 1. API reference (exact signatures and availability)

All of these are **iOS 26.0+** unless marked otherwise. "Gate" means they must be wrapped in `if #available(iOS 26.0, *)` because our target is iOS 17.

### 1.1 Glass effect on custom views

| API | Declaration (from Apple doc JSON) | iOS | Doc |
|---|---|---|---|
| `glassEffect(_:in:)` | `nonisolated func glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape()) -> some View` | 26.0 | [/swiftui/view/glasseffect(_:in:)](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)) |
| `glassEffect(_:in:isEnabled:)` | **does not exist** (doc 404). To switch glass off, pass `Glass.identity` or branch. | — | — |
| `DefaultGlassEffectShape` | `struct DefaultGlassEffectShape`, a **capsule**. You never use it directly. | 26.0 | [/swiftui/defaultglasseffectshape](https://developer.apple.com/documentation/swiftui/defaultglasseffectshape) |
| `Glass` | `struct Glass` (Equatable, Sendable) | 26.0 | [/swiftui/glass](https://developer.apple.com/documentation/swiftui/glass) |
| `Glass.regular` | `static var regular: Glass { get }`. The default; blurs and adjusts luminosity for legibility. | 26.0 | [/swiftui/glass/regular](https://developer.apple.com/documentation/swiftui/glass/regular) |
| `Glass.clear` | `static var clear: Glass { get }`. Highly translucent. Apple: "add a dimming layer… e.g. `.background(.black.opacity(0.3))`" | 26.0 | [/swiftui/glass/clear](https://developer.apple.com/documentation/swiftui/glass/clear) |
| `Glass.identity` | `static var identity: Glass { get }`. Content stays "as if no glass effect was applied". | 26.0 | [/swiftui/glass/identity](https://developer.apple.com/documentation/swiftui/glass/identity) |
| `Glass.tint(_:)` | `func tint(_ color: Color?) -> Glass`. **Takes an optional**, and `nil` means no tint. | 26.0 | [/swiftui/glass/tint(_:)](https://developer.apple.com/documentation/swiftui/glass/tint(_:)) |
| `Glass.interactive(_:)` | `func interactive(_ isEnabled: Bool = true) -> Glass`. Reacts to touch like system glass buttons. | 26.0 | [/swiftui/glass/interactive(_:)](https://developer.apple.com/documentation/swiftui/glass/interactive(_:)) |
| `GlassEffectContainer` | `@MainActor struct GlassEffectContainer<Content: View>: View` | 26.0 | [/swiftui/glasseffectcontainer](https://developer.apple.com/documentation/swiftui/glasseffectcontainer) |
| `GlassEffectContainer.init(spacing:content:)` | `init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content)` | 26.0 | [/swiftui/glasseffectcontainer/init(spacing:content:)](https://developer.apple.com/documentation/swiftui/glasseffectcontainer/init(spacing:content:)) |
| `glassEffectID(_:in:)` | `nonisolated func glassEffectID(_ id: (some Hashable & Sendable)?, in namespace: Namespace.ID) -> some View` | 26.0 | [/swiftui/view/glasseffectid(_:in:)](https://developer.apple.com/documentation/swiftui/view/glasseffectid(_:in:)) |
| `glassEffectUnion(id:namespace:)` | `@MainActor func glassEffectUnion(id: (some Hashable & Sendable)?, namespace: Namespace.ID) -> some View`. Same shape and same variant merge into one. | 26.0 | [/swiftui/view/glasseffectunion(id:namespace:)](https://developer.apple.com/documentation/swiftui/view/glasseffectunion(id:namespace:)) |
| `glassEffectTransition(_:)` | `@MainActor func glassEffectTransition(_ transition: GlassEffectTransition) -> some View` | 26.0 | [/swiftui/view/glasseffecttransition(_:)](https://developer.apple.com/documentation/swiftui/view/glasseffecttransition(_:)) |
| `GlassEffectTransition` | `.matchedGeometry` (default inside container spacing), `.materialize` (fade + materialise, for far-apart shapes), `.identity` | 26.0 | [/swiftui/glasseffecttransition](https://developer.apple.com/documentation/swiftui/glasseffecttransition) |
| `glassBackgroundEffect(in:displayMode:)` | **visionOS only**. Don't use it on iOS. | visionOS 1 | [/swiftui/view/glassbackgroundeffect(in:displaymode:)](https://developer.apple.com/documentation/swiftui/view/glassbackgroundeffect(in:displaymode:)) |
| `ConcentricRectangle` | Shape whose corners are concentric with the container or device. Use `.rect(corners:isUniform:)` and related. | 26.0 | [/swiftui/concentricrectangle](https://developer.apple.com/documentation/swiftui/concentricrectangle) |

Key facts from the docs and Apple's article ["Applying Liquid Glass to custom views"](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views):
- `glassEffect` anchors the glass to the view's **bounds**, padding included. Apply it **after** padding, frame, font and foregroundStyle ("Apply the glassEffect modifier after other modifiers that affect the appearance of the view").
- The default shape is `Capsule`. Use `.rect(cornerRadius:)` for larger components. `Shape.rect(cornerRadius:style:)` defaults to `.continuous` in the current doc.
- A **container** gives "the best rendering performance". Glass views inside it are sampled together and can blend or morph. If the container `spacing` is larger than the inner `HStack` spacing, shapes **blend together at rest**. Morphing happens when the edges are ≤ the container spacing.
- `glassEffectID` and `glassEffectTransition` only matter during insert, remove or animation (`withAnimation`).
- Performance: "Creating too many Liquid Glass effect containers and applying too many effects to views outside of containers can degrade performance. Limit the use of Liquid Glass effects onscreen at the same time."

### 1.2 Buttons

| API | Declaration | iOS | Doc |
|---|---|---|---|
| `.glass` | `static var glass: GlassButtonStyle` on `PrimitiveButtonStyle` | 26.0 | [/swiftui/primitivebuttonstyle/glass](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glass) |
| `.glassProminent` | `@MainActor static var glassProminent: GlassProminentButtonStyle`. "similar to the borderedProminent style" and uses the tint as background. | 26.0 | [/swiftui/primitivebuttonstyle/glassprominent](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glassprominent) |
| `GlassButtonStyle` | `struct GlassButtonStyle: PrimitiveButtonStyle`, with `init()` | 26.0 | [/swiftui/glassbuttonstyle](https://developer.apple.com/documentation/swiftui/glassbuttonstyle) |
| `GlassButtonStyle.init(_:)` | `init(_ glass: Glass)`, e.g. `GlassButtonStyle(.clear)` | **26.1** | [/swiftui/glassbuttonstyle/init(_:)](https://developer.apple.com/documentation/swiftui/glassbuttonstyle/init(_:)) |
| `GlassProminentButtonStyle` | `struct GlassProminentButtonStyle: PrimitiveButtonStyle`, `init()` only | 26.0 | [/swiftui/glassprominentbuttonstyle](https://developer.apple.com/documentation/swiftui/glassprominentbuttonstyle) |
| `buttonBorderShape(_:)` | `func buttonBorderShape(_ shape: ButtonBorderShape) -> some View`: `.automatic`, `.capsule`, `.circle` (iOS 17), `.roundedRectangle`, `.roundedRectangle(radius:)` | 15.0 | [/swiftui/view/buttonbordershape(_:)](https://developer.apple.com/documentation/swiftui/view/buttonbordershape(_:)) |
| `buttonSizing(_:)` | `func buttonSizing(_ sizing: ButtonSizing) -> some View`: `.automatic`, `.fitted`, `.flexible` ("filling its available space") | 26.0 | [/swiftui/view/buttonsizing(_:)](https://developer.apple.com/documentation/swiftui/view/buttonsizing(_:)) |
| `ControlSize.extraLarge` | iOS 17. The doc says it "resolves to large on platforms other than visionOS". Use `.large`. | 17.0 | [/swiftui/controlsize/extralarge](https://developer.apple.com/documentation/swiftui/controlsize/extralarge) |

Interplay:
- The glass styles are `PrimitiveButtonStyle`, so a custom `ButtonStyle` can't wrap them. Choose the style with a `@ViewBuilder` branch, as in `appButtonStyle(_:)` in §4.
- The `buttonBorderShape` doc only names bordered styles. In practice `.glass` with `.buttonBorderShape(.circle)` is the common round glass icon button, but check it on device. The default glass button shape is a capsule.
- **Tint** colours the background of `.glassProminent`. HIG: "To emphasize primary actions, apply color to the background rather than to symbols or text… Refrain from adding color to the background of multiple controls."
- Full-width buttons: either `.frame(maxWidth: .infinity)` on the **label** (works on every iOS) or `.buttonSizing(.flexible)` (iOS 26 only, and only "certain styles" adapt). We use the label frame.

### 1.3 Tab bar

| API | Declaration | iOS | Doc |
|---|---|---|---|
| `TabView` + `.tabItem { Label }` + `.tag` | the classic API. **Renders as the floating Liquid Glass tab bar on iOS 26** when built with SDK 26. | 13.0 | [/swiftui/view/tabitem(_:)](https://developer.apple.com/documentation/swiftui/view/tabitem(_:)) (not deprecated) |
| `Tab` | `struct Tab<Value, Content, Label>`, e.g. `init(_ titleKey: LocalizedStringKey, systemImage: String, value: Value, @ViewBuilder content: () -> Content)` | **18.0** | [/swiftui/tab](https://developer.apple.com/documentation/swiftui/tab) |
| `TabRole.search` | `static var search: TabRole`. The system moves the search tab to the trailing end. Needs `Tab(…, role: .search)`. | 18.0 | [/swiftui/tabrole/search](https://developer.apple.com/documentation/swiftui/tabrole/search) |
| `tabBarMinimizeBehavior(_:)` | `nonisolated func tabBarMinimizeBehavior(_ behavior: TabBarMinimizeBehavior) -> some View`: `.automatic`, `.never`, `.onScrollDown`, `.onScrollUp` | 26.0 | [/swiftui/view/tabbarminimizebehavior(_:)](https://developer.apple.com/documentation/swiftui/view/tabbarminimizebehavior(_:)) |
| `tabViewBottomAccessory(content:)` | `func tabViewBottomAccessory<Content: View>(@ViewBuilder content: () -> Content) -> some View` (always shown) | 26.0, iOS/iPadOS/Catalyst only | [/swiftui/view/tabviewbottomaccessory(content:)](https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(content:)) |
| `tabViewBottomAccessory(isEnabled:content:)` | `func tabViewBottomAccessory<Content: View>(isEnabled: Bool, @ViewBuilder content: () -> Content) -> some View` | **26.1** | [/swiftui/view/tabviewbottomaccessory(isenabled:content:)](https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(isenabled:content:)) |
| `TabViewBottomAccessoryPlacement` | env `\.tabViewBottomAccessoryPlacement`: `.expanded` / `.inline` | 26.0 | [/swiftui/tabviewbottomaccessoryplacement](https://developer.apple.com/documentation/swiftui/tabviewbottomaccessoryplacement) |

- Because of the iOS 17 target, `Tab {}` needs a second, iOS 18-gated `TabView`. That isn't worth it, since we don't need a search tab. **Use `.tabItem` + `.tag`.** It gets the glass tab bar for free. Apple's examples all use `Tab`, and no doc says `.tabItem` loses anything visual. `tabBarMinimizeBehavior` is applied to the `TabView`, and we don't use it anyway (§3.8).
- HIG tab bars: "Use a tab bar to support navigation, not to provide actions", "Make sure the tab bar is visible", "Prefer filled symbols", and avoid giving tab labels and the content background a similar colour ([HIG Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)).

### 1.4 Toolbars, bars, scroll edges

| API | Declaration | iOS | Doc |
|---|---|---|---|
| Toolbar items | `ToolbarItem` / `ToolbarItemGroup` buttons **get glass automatically**. Items in one group share one glass background. | 14+ (glass on 26) | [Landmarks sample](https://developer.apple.com/documentation/swiftui/landmarks-building-an-app-with-liquid-glass) |
| `ToolbarSpacer` | `init(_ sizing: SpacerSizing = .flexible, placement: ToolbarItemPlacement = .automatic)`; `SpacerSizing.fixed / .flexible` | 26.0 (iOS, iPadOS, macOS) | [/swiftui/toolbarspacer](https://developer.apple.com/documentation/swiftui/toolbarspacer) |
| `sharedBackgroundVisibility(_:)` | on **ToolbarContent**: `func sharedBackgroundVisibility(_ visibility: Visibility) -> some ToolbarContent`. Hiding it puts the item in its own group. | 26.0 | [/swiftui/toolbarcontent/sharedbackgroundvisibility(_:)](https://developer.apple.com/documentation/swiftui/toolbarcontent/sharedbackgroundvisibility(_:)) |
| `scrollEdgeEffectStyle(_:for:)` | `func scrollEdgeEffectStyle(_ style: ScrollEdgeEffectStyle?, for edges: Edge.Set) -> some View`: `.automatic`, `.soft`, `.hard` | 26.0 | [/swiftui/view/scrolledgeeffectstyle(_:for:)](https://developer.apple.com/documentation/swiftui/view/scrolledgeeffectstyle(_:for:)) |
| `scrollEdgeEffectHidden(_:for:)` | `func scrollEdgeEffectHidden(_ hidden: Bool = true, for edges: Edge.Set = .all) -> some View` | 26.0 | [/swiftui/view/scrolledgeeffecthidden(_:for:)](https://developer.apple.com/documentation/swiftui/view/scrolledgeeffecthidden(_:for:)) |
| `safeAreaBar(edge:…)` (vertical) | `func safeAreaBar(edge: VerticalEdge, alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> some View) -> some View`. Like `safeAreaInset`, but it **also extends the scroll edge effect** under the custom bar. | 26.0 | [/swiftui/view/safeareabar(edge:alignment:spacing:content:)-9hwgb](https://developer.apple.com/documentation/swiftui/view/safeareabar(edge:alignment:spacing:content:)-9hwgb) |
| `safeAreaBar(edge:…)` (horizontal) | same with `HorizontalEdge` and `VerticalAlignment` | 26.0 | [/swiftui/view/safeareabar(edge:alignment:spacing:content:)](https://developer.apple.com/documentation/swiftui/view/safeareabar(edge:alignment:spacing:content:)) |
| `backgroundExtensionEffect()` | `@MainActor func backgroundExtensionEffect() -> some View`. Mirrors and blurs a view under sidebars and inspectors. **Not useful for us** (no split view, no hero image). | 26.0 | [/swiftui/view/backgroundextensioneffect()](https://developer.apple.com/documentation/swiftui/view/backgroundextensioneffect()) |
| `navigationSubtitle(_:)` | gained iOS in 26.0 | 26.0 (iOS) | [/swiftui/view/navigationsubtitle(_:)](https://developer.apple.com/documentation/swiftui/view/navigationsubtitle(_:)) |
| `searchToolbarBehavior(_:)` | `.automatic` / `.minimize` | 26.0 | [/swiftui/view/searchtoolbarbehavior(_:)](https://developer.apple.com/documentation/swiftui/view/searchtoolbarbehavior(_:)) |
| `ToolbarContentBuilder.buildLimitedAvailability(_:)` | only for `CustomizableToolbarContent`, **iOS 17.5** | 17.5 | [/swiftui/toolbarcontentbuilder](https://developer.apple.com/documentation/swiftui/toolbarcontentbuilder) |

The last row means `if #available(iOS 26.0, *) { ToolbarSpacer(...) }` *inside* `.toolbar { }` is fragile with plain `ToolbarItem`s, which are not customizable. Don't use `ToolbarSpacer` or `sharedBackgroundVisibility`. Use separate `ToolbarItem`s and `ToolbarItemGroup`s. The system groups them sensibly.

### 1.5 Sheets and controls

- Sheets: "Modal views like sheets… adopt Liquid Glass… half sheets are inset from the edge of the display… When a half sheet expands to full height, it transitions to a more opaque appearance" ([Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)). `presentationDetents(_:)` (iOS 16) is unchanged. "Audit the backgrounds of sheets… remove those custom background views." So on iOS 26 **don't** set `.presentationBackground(...)` (iOS 16.4) or paint a full-bleed colour inside the sheet. Our `ConfirmSheet` currently paints `Theme.raise`; use `sheetSurface()`.
- Toggle and Slider: "the knob transforms into Liquid Glass during interaction". The segmented `Picker` and menus are glass on 26, automatically. Only set `.tint(Theme.acc)`.
- Lists and forms: larger row height, larger section radius, and **section headers are no longer uppercased** ("adopting title-style capitalization"). Our own `SectionLabel` uppercases; keep that inside cards but don't rely on List header casing.
- `UIDesignRequiresCompatibility` (Info.plist) would switch Liquid Glass **off**. It is not in `ios/project.yml`; keep it that way.

---

## 2. Apple HIG guidance (what applies to us)

From [HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials) (updated 9 Sep 2025), [HIG Color → Liquid Glass color](https://developer.apple.com/design/human-interface-guidelines/color) and [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass):

1. **Layering.** "Liquid Glass forms a distinct functional layer for controls and navigation elements… that floats above the content layer." "**Don't use Liquid Glass in the content layer**… use standard materials for elements in the content layer, such as app backgrounds." Exception: transient controls such as sliders and toggles.
2. **Sparingly.** "Standard components… pick up the appearance automatically. If you apply Liquid Glass effects to a custom control, do so sparingly… Limit these effects to the most important functional elements."
3. **Regular vs clear.** Use regular for anything with text ("components with a significant amount of text"). Use clear only over media, with a 35 % dark dimming layer on bright content. **We use only `.regular`.**
4. **Standard materials** (ultraThin, thin, regular, thick) are for structure in the content layer. "Use vibrant colors on top of materials": `label` / `secondaryLabel` / `tertiaryLabel`, and avoid quaternary on thin materials. "Thicker materials… better contrast for text."
5. **Colour on glass.** Glass has no colour of its own and takes it from what's behind. "Apply color sparingly… reserve it for… status indicators or primary actions. To emphasize primary actions, apply color to the background rather than to symbols or text." Tab bar and toolbar symbols go monochrome automatically (dark over light content, light over dark).
6. **Custom colours** need light and dark variants plus an increased-contrast variant. `Theme.dynamic` already covers light and dark. For Increase Contrast we strengthen borders (§4 `CardSurface`).
7. **Accessibility.** "people can choose a preferred look for Liquid Glass in their device's settings" (Clear or Tinted since iOS 26.1), "or turn on accessibility settings that reduce transparency or motion… If you use standard components… this experience adapts automatically. Ensure you test your app's custom elements." Standard materials become solid with Reduce Transparency. For custom `glassEffect`, third-party guides report the system frosts it more, but Apple doesn't spell this out. **Test on device with Reduce Transparency, Increase Contrast, Reduce Motion, and both appearance choices.**
8. **Rounded, concentric shapes.** "Consider aligning the shape of controls with other rounded elements". Use larger radii (cards 24, tiles 18 and 14, capsule buttons), with continuous corners.
9. **Toolbars**: group related items, use icons instead of text for common actions, give every icon an `accessibilityLabel`, and don't mix text and icons in one group.

---

## 3. Design guide for this app

### 3.1 Layers at a glance

| Layer | What | How |
|---|---|---|
| System glass (free) | tab bar, nav bar and large title, toolbar buttons (gear, filter menu), sheets, alerts, `confirmationDialog`, menus, segmented pickers, toggles, sliders, search field | nothing. Don't override backgrounds. |
| Custom glass (sparingly) | action buttons, filter or sort chips, the toast and status pill, at most one hero card per screen, small round icon buttons in rows ("Проверить сейчас") | `appButtonStyle`, `GlassChip` + `GlassChipRow`, `floatingGlass`, `heroGlassCard`, `GlassIconButton` (§4) |
| Content | cards, tiles, rows, charts, banners, tone chips | `glassCard()` = `Material.regular` + rim; `innerTile()` = quiet fill. No `glassEffect`. |
| Background | one soft gradient per screen | `appScreenBackground()` |

### 3.2 App background
- Use `Theme.bg` plus two large radial glows: green `Theme.acc` top-left (16 % light, 20 % dark) and blue `Theme.info` bottom-right (10 % light, 16 % dark). It is static, cheap and works in both schemes, because `Theme` colours are dynamic and `.opacity` keeps them dynamic.
- Put it **behind the scroll view, ignoring safe areas**. Content then scrolls under the transparent nav bar and the floating tab bar, and the glass has colour to refract. Replace each `Theme.bg.ignoresSafeArea()` background (SummaryView, SettingsView) with `.appScreenBackground()`. Login, code entry and Lock can use `AppBackground()` too. The privacy cover keeps opaque `Theme.bg` on purpose.
- For `List` and `Form` (Settings, Журнал, Устройства if built on List), `.scrollContentBackground(.hidden)` is required, otherwise the grouped background hides the gradient. `appScreenBackground()` does both.

### 3.3 Cards (content layer)
- Use `Material.regular` (`.regularMaterial`) in a continuous rounded rect with **radius 24**, 16 pt padding and 14 pt spacing between cards.
- Add a 1 pt "specular" rim: a white gradient, 80 %→30 % in light and 16 %→4 % in dark. With **Increase Contrast** use a solid `Theme.border2` instead (`@Environment(\.colorSchemeContrast)`).
- An optional tone tint is a 7 % (light) or 12 % (dark) wash of the level colour, for example a red-tinted "Роутер не на связи" card. Keep the existing 3 pt accent line on top if desired. It still works with `clipShape`.
- **No shadows on material cards.** A `.shadow` on a translucent card also shadows the text inside it, and it costs performance in a scrolling `LazyVStack`. The rim plus material gives enough separation on the gradient.
- `Card` (Components/Card.swift) only needs its `.background(Theme.card)` + border overlay swapped for `.modifier(CardSurface(...))`. Its API stays the same.

### 3.4 Hero card (at most one per screen)
- «Сводка»: the verdict card («Всё работает» / «Требует внимания» / «Есть проблема») uses `heroGlassCard(tint: Theme.dot(tone))`. That is regular glass tinted at 22 % with the tone colour. On iOS < 26 it falls back to a tinted material card.
- Text on it: `Theme.text` for the title, `Theme.levelText(tone)` for the status word, always next to the SF Symbol (`Theme.symbol(tone)`), because colour alone isn't enough.
- Other screens have no hero, or the VPN "current server" card if it looks right. Never two.

### 3.5 Tiles and stats
- **Inside a card** (router meters, stats grid, LatencyTile, ServiceTile): use `innerTile(tone:)`, a 5 % `Color.primary` fill or the tone's soft fill plus ring, with radius 14. **Never glass on glass or material on material.**
- **Stand-alone in a grid** (only if a screen shows tiles outside a card): use `glassTile()`, which is material at radius 18.
- Big values: `.font(.title2.weight(.semibold)).monospacedDigit()`, with the unit in a smaller `Theme.dim` font in the same `Text` concatenation or HStack.

### 3.6 Chips and filters
- 2–4 fixed, mutually exclusive options. Examples: Устройства «Все / В сети / Не в сети / Ограничены»; history range «Сутки / 7 дней / 30 дней»; zapret strategy «1 / 2 / 3». Use **`Picker(...).pickerStyle(.segmented)`**. It is system glass on iOS 26, accessible, and needs no code.
- More options, or a scrolling set (VPN sort «По пингу / По имени / YouTube / Discord / Telegram», Журнал type filter): use `GlassChipRow { GlassChip(...) }`. That is interactive regular glass, with the selected chip tinted `Theme.acc` and its label in `Theme.onAcc`, all inside **one** `GlassEffectContainer(spacing: 4)` with an HStack spacing of 8. The smaller container spacing keeps chips separate at rest.
- Chips only **select** (filter or sort). They never trigger router actions.
- Tone chips that show status («без интернета», «мимо VPN», «по расписанию») are **content**: keep the existing `ToneChip` (soft fill plus ring). Not glass, not tappable.

### 3.7 Buttons

| Kind (`ActionButtonStyle.Kind`) | Used for | iOS 26 | iOS 17–25 |
|---|---|---|---|
| `.primary` | «Подключить», «Сохранить», the main confirm button in the 428 sheet | `.glassProminent` + `.tint(Theme.acc)` + label `Theme.onAcc`, `.controlSize(.large)` | existing green fill |
| `.secondary` | «Проверить», «Отмена», «Обновить подписки» | `.glass` + label `Theme.text` | existing |
| `.destructiveOutline` | «Перезагрузить роутер», «Выключить интернет» on a card | `.glass` + label `Theme.err` | existing red outline |
| `.destructiveFill` | confirm button when `danger == critical` | `.glassProminent` + `.tint(Theme.errFill)` + white label | existing red fill |

- Only **one** prominent (coloured) button per group or card. HIG says to "refrain from adding color to the background of multiple controls". On «Сводка» the action card is therefore: «Проверить» (glass), «Перезапустить VPN» (glass), «Обновить подписки» (glass), «Перезагрузить роутер» (glass, red label). There is no green prominent button there. Prominent is for confirming in sheets and for «Подключить».
- Colour contrast: `Theme.onAcc` on `Theme.acc` is white on #059669 (light) and #052E1F on #34D399 (dark). White on `errFill` #DC2626 is 4.8:1. The label colour is also set **on the label itself** in `AppButton`, so it wins over any style default.
- Disabled: system dimming. Busy: a `ProgressView` in the label, which `AppButton` handles.
- The plan's safety rules don't change. Dangerous buttons still go through the server's 428 confirm flow, with Face ID for `danger: critical`. Nothing fires from swipe or pull. `.refreshable` only re-reads data.

### 3.8 Tab bar and navigation
- Five tabs: **Сводка** (`gauge.with.dots.needle.33percent`), **VPN** (`lock.shield`), **Устройства** (`laptopcomputer.and.iphone`), **Обход** (`arrow.triangle.branch`), **Журнал** (`list.bullet.rectangle`). Settings is the gear in the top-trailing toolbar, as now (plan §2 «Настройки (шестерёнка)»). Put it on every tab's root, or at least on Сводка.
- One `NavigationStack` per tab, so state is kept per tab (HIG). Use `.tint(Theme.acc)` on the `TabView` for the selected tab. It is green, and content is mostly neutral, so differentiation is fine.
- **Don't** set `tabBarMinimizeBehavior`. Keep the bar always visible: there are only 5 tabs, and HIG says "Make sure the tab bar is visible". Don't use `tabViewBottomAccessory`: it suits a persistent mini-player, while our statuses are transient. Use the toast or pill (§3.9).
- Large titles (`.navigationBarTitleDisplayMode(.large)`). On iOS 26, `navigationSubtitle` could show «обновлено 12 с назад», but it is iOS 26-only and the current `UpdatedLabel` is enough.
- Устройства search: use `.searchable(text:prompt: "Имя, IP или MAC")` on the stack root. The system places and styles it (glass on 26). Don't build a custom field.

### 3.9 Floating elements
- **Toast** («VPN перезапускается.»): use `ToastView` content with `.floatingGlass(tint: Theme.dot(tone))`, a glass capsule tinted 25 %. Put the overlay **inside each tab's NavigationStack** (or the screen root), not on the `TabView`. Its bottom safe area then already includes the floating tab bar, and the toast sits above it.
- **"VPN перезапускается…" pill** (plan §2: while it is up, the other dangerous buttons are disabled): show the same `floatingGlass` capsule pinned under the nav bar or above the tab bar via `.safeAreaInset(edge: .bottom)`. `safeAreaBar` is the iOS 26 variant that also extends the scroll-edge blur. Make it non-interactive, with no `.interactive()`.
- No floating action bar for router actions. They live in cards, where they are deliberate and visible together with their explanation.

### 3.10 Status colours on glass and material
- On material cards: `Theme.levelText(tone)` for coloured words and `Theme.dot(tone)` for dots and bars. These are the existing AA-tuned tokens. Always add the symbol or word (`Theme.symbol` / `Theme.levelWord`).
- On tinted glass (hero, toast): use **neutral text** (`Theme.text`). Colour goes only in the symbol and the tint. Coloured text on coloured glass loses contrast.
- Don't place green chips or text over the green glow of the background at rest. The glow sits top-left under the large title, where only neutral text appears.

### 3.11 Typography and numbers (owner's Summary fixes)
- Replace `.font(.system(.body, design: .monospaced))` in `FactRow` and elsewhere with `.monospacedDigit()` (iOS 15). Only the digits become fixed-width, so «9 в сети» and «64 мс» lose the wide gaps.
- Use `.contentTransition(.numericText())` (iOS 17) with `.animation(.default, value:)` on live numbers (speed, ping). This rolling-digit effect is part of the iOS 26 feel, and it respects Reduce Motion.
- Decimal comma («9,2 ГБ») belongs in the RouterCore formatter (one place, tested), not in views.
- Wrapping «Проверка через VPN · Задержка»: use `ViewThatFits(in: .horizontal) { oneLine; twoLines }` (iOS 16). Alternatively, put the label in its own `Text` with `.lineLimit(1).minimumScaleFactor(0.85)` and the value in a separate trailing `Text`. Never let the "·" break mid-line.

### 3.12 Screens (layout reference: the HTML mockups; style per this guide)
- **Сводка**: hero verdict card, then cards (server, check through VPN, services, internet, router, subscription, mini-chart, events, devices), then the action card with glass buttons.
- **VPN**: mode card; `GlassChipRow` for sort; server groups as cards with rows; each row has its ping (`monospacedDigit`) and a `GlassIconButton("bolt.horizontal", "Проверить сейчас")`. Tap opens the server detail, where «Подключить» is `.primary` (sheet confirm). «Напрямую, без VPN» is `.destructiveOutline` with confirm and Face ID. The /vds own-servers card is read-only content. The speed test uses a `.secondary` button, with the caption about 35 s and subscription traffic.
- **Устройства**: `.searchable`, a segmented filter, a «Новые за неделю» card, then band sections as cards. In the device detail, «Выключить интернет» is `.destructiveOutline` and its confirm is red prominent. Rename uses a text field plus `.primary` «Сохранить».
- **Обход**: system `Toggle`s (they get glass knobs). Every toggle change goes through confirm, never a direct change. The strategy is a segmented picker. The MyDirect list is in a card with a `.secondary` «Добавить сайт» button.
- **Журнал**: List or LazyVStack inside cards, a type-filter chip row, and `.monospacedDigit()` times.
- **Настройки**: a `Form` with `appScreenBackground()` and system toggles, including the new «Скрывать в переключателе приложений» toggle (default **off**).

---

## 4. Code: tiny design system (`ios/Router/Components/GlassKit.swift`)

This file was type-checked on Linux (Swift 6.2, `-swift-version 5`) against a hand-written SwiftUI stub with the exact signatures above. That catches the result-builder and `if #available` structure, opaque types and generic inference. Availability attributes are ignored on Linux, so availability was **checked by hand**: every iOS 26 symbol (`Glass`, `glassEffect`, `GlassEffectContainer`, `.glass`, `.glassProminent`) is used only inside `if #available(iOS 26.0, *)`. Everything else is iOS ≤ 17: `scrollContentBackground` 16, `scrollClipDisabled` 17, `ButtonBorderShape.circle` 17, `Material` / `AnyShapeStyle` / `background(_:in:)` 15. It uses the existing `Theme`, `Tone` and `ActionButtonStyle`.

```swift
import SwiftUI
import RouterCore

// Liquid Glass design kit for «Роутер» (stage 4).
// Deployment target iOS 17, built with the iOS 26 SDK, Swift 5 mode.
// Rule of thumb: real Liquid Glass (glassEffect / .glass button styles) only on the
// control layer — buttons, chips, floating toasts. Content cards use standard materials.

// MARK: - Metrics

enum Metrics {
    static let screenPadding: CGFloat = 16
    static let cardSpacing: CGFloat = 14
    static let cardRadius: CGFloat = 24
    static let tileRadius: CGFloat = 18
    static let innerRadius: CGFloat = 14
}

// MARK: - App background (content layer, under everything)

/// Soft tinted gradient: `bg` plus a green glow top-left and a blue glow bottom-right.
/// Gives Liquid Glass (tab bar, toolbar, buttons) something to refract, in light and dark.
struct AppBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            Theme.bg
            RadialGradient(
                colors: [Theme.acc.opacity(dark ? 0.20 : 0.16), Color.clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 460
            )
            RadialGradient(
                colors: [Theme.info.opacity(dark ? 0.16 : 0.10), Color.clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension View {
    /// Screen root (ScrollView, List or Form inside a NavigationStack): hide the default
    /// list background and put the app gradient behind everything, edge to edge.
    func appScreenBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background {
                AppBackground()
            }
    }
}

// MARK: - Cards (content layer: material, not Liquid Glass)

/// Card surface: regular material + optional level tint + a light «rim» on top.
/// Reduce Transparency makes the material opaque by itself; Increase Contrast gets a solid border.
struct CardSurface: ViewModifier {
    var cornerRadius: CGFloat = Metrics.cardRadius
    var tint: Color? = nil
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let dark = scheme == .dark
        content
            .background {
                shape
                    .fill(Material.regular)
                    .overlay {
                        if let tint = tint {
                            shape.fill(tint.opacity(dark ? 0.12 : 0.07))
                        }
                    }
            }
            .overlay {
                if contrast == .increased {
                    shape.strokeBorder(Theme.border2, lineWidth: 1)
                } else {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(dark ? 0.16 : 0.80),
                                Color.white.opacity(dark ? 0.04 : 0.30)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                }
            }
    }
}

/// One hero element per screen may be real glass (e.g. the verdict on «Сводка»).
/// iOS 26: tinted regular glass; earlier: the card material.
struct HeroGlassSurface: ViewModifier {
    var cornerRadius: CGFloat = Metrics.cardRadius
    var tint: Color? = nil

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    Glass.regular.tint(tint?.opacity(0.22)),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
        } else {
            content
                .modifier(CardSurface(cornerRadius: cornerRadius, tint: tint))
        }
    }
}

/// Tile inside a card (stats, meters, service tiles): a quiet fill, never glass on glass.
struct TileSurface: ViewModifier {
    var tone: Tone? = nil
    var cornerRadius: CGFloat = Metrics.innerRadius

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(tone.map { Theme.soft($0) } ?? Color.primary.opacity(0.05), in: shape)
            .overlay {
                shape.strokeBorder(tone.map { Theme.ring($0) } ?? Color.primary.opacity(0.06), lineWidth: 1)
            }
    }
}

extension View {
    /// Padded card: `VStack { … }.glassCard()`.
    func glassCard(cornerRadius: CGFloat = Metrics.cardRadius, tint: Color? = nil) -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(CardSurface(cornerRadius: cornerRadius, tint: tint))
    }

    /// The single hero card of a screen (real glass on iOS 26).
    func heroGlassCard(cornerRadius: CGFloat = Metrics.cardRadius, tint: Color? = nil) -> some View {
        self
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(HeroGlassSurface(cornerRadius: cornerRadius, tint: tint))
    }

    /// Stand-alone tile in a grid (outside a card): smaller material card.
    func glassTile(cornerRadius: CGFloat = Metrics.tileRadius, tint: Color? = nil) -> some View {
        self
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(CardSurface(cornerRadius: cornerRadius, tint: tint))
    }

    /// Tile inside a card.
    func innerTile(tone: Tone? = nil, cornerRadius: CGFloat = Metrics.innerRadius) -> some View {
        self
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(TileSurface(tone: tone, cornerRadius: cornerRadius))
    }
}

// MARK: - Chips and filters (control layer: interactive glass in a container)

/// Surface of one chip. iOS 26: interactive glass, selected = accent-tinted glass.
struct ChipSurface: ViewModifier {
    let isSelected: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            let glass: Glass = isSelected ? Glass.regular.tint(Theme.acc).interactive() : Glass.regular.interactive()
            content
                .foregroundStyle(isSelected ? Theme.onAcc : Theme.text)
                .glassEffect(glass, in: Capsule())
        } else {
            content
                .foregroundStyle(isSelected ? Theme.onAcc : Theme.text)
                .background(isSelected ? AnyShapeStyle(Theme.acc) : AnyShapeStyle(Material.thin), in: Capsule())
                .overlay {
                    Capsule().strokeBorder(isSelected ? Color.clear : Theme.border, lineWidth: 1)
                }
        }
    }
}

extension View {
    func glassChip(selected: Bool) -> some View {
        modifier(ChipSurface(isSelected: selected))
    }
}

/// A tappable filter / sort chip («Все», «В сети», «По пингу»…). Selection only — never an action.
struct GlassChip: View {
    let title: String
    var systemImage: String? = nil
    var count: Int? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
                Text(title)
                if let count = count {
                    Text(String(count))
                        .monospacedDigit()
                        .opacity(0.7)
                }
            }
            .font(.subheadline.weight(isSelected ? .semibold : .regular))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassChip(selected: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Horizontal chip row. iOS 26: one GlassEffectContainer for all chips (one render pass,
/// shapes can morph). Container spacing is smaller than the HStack spacing so chips do not
/// melt together at rest. Place it outside the 16-pt padded column: it pads itself.
struct GlassChipRow<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            row
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.vertical, 4)
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private var row: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 4) {
                HStack(spacing: 8) {
                    content
                }
            }
        } else {
            HStack(spacing: 8) {
                content
            }
        }
    }
}

// MARK: - Buttons

extension ActionButtonStyle.Kind {
    /// Label colour per kind — the same mapping as ActionButtonStyle (contract §6).
    var labelColor: Color {
        switch self {
        case .primary:
            return Theme.onAcc
        case .secondary:
            return Theme.text
        case .destructiveOutline:
            return Theme.err
        case .destructiveFill:
            return Color.white
        }
    }
}

extension View {
    /// The app's four button kinds. iOS 26: system Liquid Glass button styles
    /// (press reaction, morphing, accessibility settings come for free); earlier: ActionButtonStyle.
    /// Full width: give the label `.frame(maxWidth: .infinity)` (AppButton does it).
    @ViewBuilder
    func appButtonStyle(_ kind: ActionButtonStyle.Kind) -> some View {
        if #available(iOS 26.0, *) {
            switch kind {
            case .primary:
                self
                    .buttonStyle(.glassProminent)
                    .tint(Theme.acc)
                    .foregroundStyle(kind.labelColor)
                    .controlSize(.large)
            case .secondary, .destructiveOutline:
                self
                    .buttonStyle(.glass)
                    .foregroundStyle(kind.labelColor)
                    .controlSize(.large)
            case .destructiveFill:
                self
                    .buttonStyle(.glassProminent)
                    .tint(Theme.errFill)
                    .foregroundStyle(kind.labelColor)
                    .controlSize(.large)
            }
        } else {
            self.buttonStyle(ActionButtonStyle(kind: kind))
        }
    }
}

/// Full-width action button: icon + text, optional spinner while busy.
struct AppButton: View {
    let title: String
    var systemImage: String? = nil
    var kind: ActionButtonStyle.Kind = .primary
    var isBusy: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                } else if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
            }
            // Colour on the label itself: wins over any style default on every iOS version.
            .foregroundStyle(kind.labelColor)
            .frame(maxWidth: .infinity)
        }
        .appButtonStyle(kind)
    }
}

/// Small round icon button inside content (e.g. «Проверить сейчас» next to a server row).
struct GlassIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 22, height: 22)
        }
        .glassIconStyle()
        .accessibilityLabel(accessibilityLabel)
    }
}

extension View {
    @ViewBuilder
    func glassIconStyle() -> some View {
        if #available(iOS 26.0, *) {
            self
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
        } else {
            self
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
        }
    }
}

// MARK: - Floating elements (toast, «VPN перезапускается…» pill)

/// Floating capsule over content: the right place for real glass.
struct FloatingSurface: ViewModifier {
    var tint: Color? = nil

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(Glass.regular.tint(tint?.opacity(0.25)), in: Capsule())
        } else {
            content
                .background(Material.regular, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(Theme.border, lineWidth: 1)
                }
        }
    }
}

extension View {
    func floatingGlass(tint: Color? = nil) -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .modifier(FloatingSurface(tint: tint))
    }
}

// MARK: - Sheets

extension View {
    /// iOS 26: no custom background, so the system Liquid Glass sheet shows (inset at .medium,
    /// more opaque at .large). Earlier iOS: the opaque `raise` colour as before.
    @ViewBuilder
    func sheetSurface() -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            self.background {
                Theme.raise.ignoresSafeArea()
            }
        }
    }
}
```

### 4.1 Why it is written this way (compile rules)
- `if #available` inside a `@ViewBuilder` works because `ViewBuilder.buildLimitedAvailability` (iOS 14) erases the branch to `AnyView`. That means each helper returns `some View` and contains **both** branches. `ViewModifier.body(content:)` is already a builder; the explicit `@ViewBuilder` is harmless and documents intent.
- **Never store a `Glass` (or any iOS 26 type) in a stored property.** Stored properties can't be `@available`-limited. Pass our own values (`Color?`, `Bool`, `Tone`) and build the `Glass` inside the `#available` branch, as `ChipSurface` does with `let glass: Glass = …`.
- `glassEffect(_:in:)` takes `some Shape`, so pass a concrete shape (`Capsule()`, `RoundedRectangle(cornerRadius:style:)`). If the shape must vary at run time, `AnyShape` (iOS 16) works for `glassEffect` and `.fill`. `AnyShape` is **not** an `InsettableShape`, though, so `background(_:in:)` and `strokeBorder` won't accept it. Use `.background { shape.fill(...) }` and `.stroke` there, or branch with two concrete shapes.
- Ternaries with implicit members (`isSelected ? .regular.tint(...) : .regular`) type-check, but spelling `Glass.regular` keeps errors readable.
- The glass button styles are `PrimitiveButtonStyle`s. A custom `ButtonStyle` can't wrap them, so the kind is chosen with a view-level `switch` (`appButtonStyle`).
- `if #available` inside `.toolbar { }`: avoid it (see §1.4). Branch outside, on the view.

### 4.2 Usage snippets

**Tabs** (`App/MainTabView.swift`; works on iOS 17, glass tab bar on 26):
```swift
enum AppTab: Hashable {
    case summary, vpn, devices, bypass, journal
}

struct MainTabView: View {
    @State private var tab: AppTab = .summary

    var body: some View {
        TabView(selection: $tab) {
            SummaryView()
                .tabItem { Label("Сводка", systemImage: "gauge.with.dots.needle.33percent") }
                .tag(AppTab.summary)
            VPNView()
                .tabItem { Label("VPN", systemImage: "lock.shield") }
                .tag(AppTab.vpn)
            DevicesView()
                .tabItem { Label("Устройства", systemImage: "laptopcomputer.and.iphone") }
                .tag(AppTab.devices)
            BypassView()
                .tabItem { Label("Обход", systemImage: "arrow.triangle.branch") }
                .tag(AppTab.bypass)
            JournalView()
                .tabItem { Label("Журнал", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.journal)
        }
        .tint(Theme.acc)
    }
}
```

**Screen skeleton**:
```swift
NavigationStack {
    ScrollView {
        LazyVStack(alignment: .leading, spacing: Metrics.cardSpacing) {
            VerdictCard()                      // inside: … .heroGlassCard(tint: Theme.dot(verdict.tone))
            ServerCard()                       // inside: … .glassCard()
            ActionsCard()
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.bottom, 24)
    }
    .appScreenBackground()
    .refreshable { await store.refreshAll() }   // re-read only, never an action
    .navigationTitle("Сводка")
    .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
            Button { store.isSettingsPresented = true } label: { Image(systemName: "gearshape") }
                .accessibilityLabel("Настройки")      // no buttonStyle: the system gives it glass
        }
    }
    .overlay(alignment: .bottom) { ToastOverlay() }   // inside the stack → above the tab bar
}
```

**Filters**:
```swift
Picker("Показать", selection: $filter) {
    Text("Все").tag(DeviceFilter.all)
    Text("В сети").tag(DeviceFilter.online)
    Text("Не в сети").tag(DeviceFilter.offline)
    Text("Ограничены").tag(DeviceFilter.limited)
}
.pickerStyle(.segmented)

GlassChipRow {
    ForEach(SortKey.allCases) { key in
        GlassChip(title: key.title, isSelected: sort == key) {
            withAnimation(.snappy) { sort = key }
        }
    }
}
```

**Buttons**: in the existing `ActionButton` (RouterCards.swift), replace `.buttonStyle(ActionButtonStyle(kind: kind))` with `.appButtonStyle(kind)`. Add `.frame(maxWidth: .infinity)` and `.foregroundStyle(kind.labelColor)` to the label HStack, or use `AppButton` directly. Do the same in `ConfirmSheet` and swap its `.background { Theme.raise.ignoresSafeArea() }` for `.sheetSurface()`.

**Toast**: in `ToastView`, replace the current background with `.floatingGlass(tint: Theme.dot(toast.tone))` and keep the text `Theme.text`.

**Privacy cover as a setting** (owner decision 3):
```swift
// AppSettings
static let hideInSwitcherKey = "hideInSwitcher"          // default false

// PrivacyCoverModifier
@AppStorage(AppSettings.hideInSwitcherKey) private var hideInSwitcher = false
…
.overlay {
    if (hideInSwitcher && scenePhase != .active) || (includeLock && lock.isLocked) {
        PrivacyCoverView()
    }
}

// SettingsView (Form section «Защита»)
Toggle("Скрывать в переключателе приложений", isOn: $hideInSwitcher)
// footer: «Если включено, в списке открытых приложений вместо данных виден только значок.»
```

---

## 5. Pitfalls

1. **Glass on glass.** Don't put `glassEffect` on a view that already sits on glass: a chip inside the hero card, a glass button in a toolbar, or glass inside a sheet's content on iOS 26 (the sheet is already glass). Inside the hero card use plain or `.borderless` buttons or tiles. In toolbars use plain `Button`s with no style.
2. **Too many glass layers.** Each `glassEffect` samples and blurs the backdrop. Keep it to about 10 or fewer glass shapes on screen. Group neighbours in one `GlassEffectContainer`, and never use glass per row in a long list (the VPN server list, Журнал). The row icon buttons in §3.12 are the limit: if a list has more than about 15 rows, make the row's whole cell tappable and drop the per-row glass button.
3. **Container spacing.** Container spacing ≥ the stack spacing makes neighbours melt into one blob at rest. Use container spacing below the stack spacing unless you want a merged group (`glassEffectUnion`).
4. **Morphing needs** the same container, `glassEffectID` with a `@Namespace`, and a `withAnimation` change. Without the container, shapes just fade.
5. **`.interactive()` only on things that are tappable.** It invites touches. The toast (tap to dismiss) may use it; the status pill and the hero card must not.
6. **Modifier order.** Apply `glassEffect` last, after `padding`, `frame`, `font` and `foregroundStyle`. Glass covers the view's bounds, so padding before it means bigger glass.
7. **Custom backgrounds kill system glass.** That covers `toolbarBackground(...)`, `UINavigationBar/UITabBar.appearance()`, `presentationBackground` on iOS 26 sheets, and full-bleed `Theme.raise` inside a sheet. Also don't set `UIDesignRequiresCompatibility`.
8. **`.clear` glass** is for media only. Over our gradient it's illegible without a dimming layer. Use `.regular`.
9. **Shadows on translucent containers** shadow every glyph inside. Avoid `.shadow` on material or glass views. If it's needed, shadow a separate opaque shape behind.
10. **Tinted glass text.** Use neutral text on tinted glass. For prominent buttons, set the label colour explicitly (`labelColor`) and check both schemes on device.
11. **iOS 26.1-only APIs** (`GlassButtonStyle(_:)`, `tabViewBottomAccessory(isEnabled:)`) need `#available(iOS 26.1, *)`, not 26.0.
12. **Lock vs app switcher.** With «Блокировка: Сразу», `AppLock.didEnterBackground` sets `isLocked` **before** iOS takes the switcher snapshot. RootView then shows `LockView`, so the switcher shows the lock screen, not data, even with the new toggle off. To honour "data not hidden by default", when `hideInSwitcher == false`, engage the immediate lock on the way **back** (`willEnterForeground`, still `.inactive`, before the first active frame) instead of at background. Keep the current behaviour when the toggle is on. Face ID on return stays as configured.
13. **The toast over the TabView** would sit under or behind the floating tab bar. Attach it inside each tab, as in §4.2.
14. **Search field placement** on iOS 26 iPhone is system-decided (top or bottom toolbar). Don't fight it; verify it doesn't cover the segmented filter.
15. **Accessibility.** Test Reduce Transparency (materials go solid; custom glass gets more frosted, so verify), Increase Contrast (`CardSurface` swaps to a solid border), Reduce Motion (morphing and numeric transitions are toned down by the system), Larger Text (cards must grow; chip rows scroll), and Settings → Display → Liquid Glass «Прозрачный / Тонированный» (26.1+).

## 6. On-device checklist (owner's iPhone 17 Pro, iOS 26)
- Light and dark, theme forced and system: the gradient is visible but quiet, cards are legible, the tab bar is legible over every screen top and bottom.
- Scroll each screen: content blurs under the nav bar (scroll edge effect) and under the tab bar, with no hard seams.
- Buttons: green prominent is legible in dark mode (dark label), the red label on `.glass` is legible, disabled states are clear.
- Chips: selection is visible without colour (weight change plus the `isSelected` trait for VoiceOver).
- Sheets: the 428 confirm at `.medium` shows inset glass; at `.large` it is opaque enough.
- App switcher: data visible with the toggle off (including with «Сразу» lock, see pitfall 12); logo cover with the toggle on.
- Reduce Transparency and Increase Contrast on: everything still legible.

## Sources
- Apple: [glassEffect(_:in:)](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)), [Glass](https://developer.apple.com/documentation/swiftui/glass), [GlassEffectContainer](https://developer.apple.com/documentation/swiftui/glasseffectcontainer), [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views), [Landmarks: Building an app with Liquid Glass](https://developer.apple.com/documentation/swiftui/landmarks-building-an-app-with-liquid-glass), [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass), [HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials), [HIG Color](https://developer.apple.com/design/human-interface-guidelines/color), [HIG Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars), [ButtonSizing](https://developer.apple.com/documentation/swiftui/buttonsizing), [ToolbarContentBuilder](https://developer.apple.com/documentation/swiftui/toolbarcontentbuilder), and the per-symbol links in §1.
- Third-party (secondary; used only for Reduce Transparency behaviour and the open `.tabItem` question): [LiquidGlassReference (GitHub)](https://github.com/conorluddy/LiquidGlassReference), [SwiftUI Liquid Glass guide (atelier-socle)](https://www.atelier-socle.com/en/articles/swiftui-liquid-glass-guide), [Donny Wals: tab bars on iOS 26](https://www.donnywals.com/exploring-tab-bars-on-ios-26-with-liquid-glass/), [createwithswift: collapsing tab bar](https://www.createwithswift.com/making-the-tab-bar-collapse-while-scrolling/).
