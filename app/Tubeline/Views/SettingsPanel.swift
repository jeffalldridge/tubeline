import SwiftUI
import TubelineCore

struct SettingsPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Tube") {
                LabeledSlider(title: "Thickness", value: $model.options.thickness, range: 0.25...3, step: 0.05,
                              format: { String(format: "%.2f×", $0) },
                              help: "Tube diameter as a multiple of the SVG stroke width")
                LabeledSlider(title: "Facets", value: $model.options.facets, range: 12...96, step: 2,
                              format: { "\(Int($0))" },
                              help: "How many flat sides go around each tube. More is smoother and heavier; shading stays round either way.")
                Toggle("Optimize mesh", isOn: $model.options.optimize)
                    .help("Collapses straight runs and flat faces into large triangles while staying within one facet of the exact shape. Much lighter in Motion.")
                Picker("Ends", selection: $model.options.caps) {
                    Text("From SVG").tag(ConversionOptions.Caps.svg)
                    Text("Round").tag(ConversionOptions.Caps.round)
                    Text("Flat").tag(ConversionOptions.Caps.flat)
                }
            }

            Section {
                Picker("Intersections", selection: intersectionPreset) {
                    Text("Crisp").tag(IntersectionPreset.crisp)
                    Text("Soft").tag(IntersectionPreset.soft)
                    Text("Round").tag(IntersectionPreset.round)
                    if intersectionPreset.wrappedValue == .custom { Text("Custom").tag(IntersectionPreset.custom) }
                }
                .pickerStyle(.segmented)
                LabeledSlider(title: "Blend", value: $model.options.fillet, range: 0...1, step: 0.05,
                              format: { $0 == 0 ? "None" : String(format: "%.2f", $0) },
                              help: "Fillet radius where separate strokes meet, as a fraction of the tube radius")
            } header: {
                Text("Where Shapes Meet")
            }

            Section("Filled Shapes") {
                Toggle("Include fills", isOn: $model.options.includeFills)
                    .help("Filled shapes with an outline become solid discs as thick as the outline")
                if model.options.includeFills {
                    Picker("Without outline", selection: $model.options.fillStyle) {
                        Text("Extrude").tag(ConversionOptions.FillStyle.extruded)
                        Text("Rounded").tag(ConversionOptions.FillStyle.rounded)
                    }
                    .help("Solid artwork such as outlined text: a straight extrusion, or a pillow as thick as the icon's strokes")
                    if model.options.fillStyle == .extruded {
                        HStack {
                            Text("Depth")
                            Spacer()
                            TextField("", value: $model.options.extrudeDepth, format: .number.precision(.fractionLength(0...2)))
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                            Text("pt").foregroundStyle(.secondary)
                        }
                        LabeledSlider(title: "Edge rounding", value: $model.options.extrudeRounding, range: 0...1, step: 0.05,
                                      format: { $0 == 0 ? "Sharp" : String(format: "%.2f", $0) },
                                      help: "Rounds the front and back edges of extrusions")
                    }
                }
            }

            Section("Look") {
                Picker("Surface", selection: $model.options.surface) {
                    Text("Solid Color").tag(ConversionOptions.Surface.solid)
                    Text("Shaded").tag(ConversionOptions.Surface.shaded)
                }
                .pickerStyle(.segmented)
                .help("Solid Color ignores scene lights; Shaded responds to them")
                ColorPicker("Color", selection: colorBinding, supportsOpacity: false)
            }

            Section("Size") {
                Picker("Frame", selection: $model.options.framing) {
                    Text("SVG Canvas").tag(ConversionOptions.Framing.canvas)
                    Text("Artwork").tag(ConversionOptions.Framing.content)
                }
                .help("What the model is centered on (and, for Fixed Size, what is scaled): the SVG canvas keeps a set of icons aligned, Artwork uses the drawing itself")
                Picker("Scale", selection: $model.options.sizing) {
                    Text("From Points").tag(ConversionOptions.Sizing.points)
                    Text("Fixed Size").tag(ConversionOptions.Sizing.fixed)
                }
                .pickerStyle(.segmented)
                if model.options.sizing == .points {
                    HStack {
                        Text("1 pt =")
                        Spacer()
                        TextField("", value: $model.options.millimetersPerPoint, format: .number.precision(.fractionLength(0...4)))
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                        Text("mm").foregroundStyle(.secondary)
                    }
                    .help("Physical size of one artwork point. Print standard is 0.3528 mm (1/72 inch).")
                } else {
                    HStack {
                        Text("Longest side")
                        Spacer()
                        TextField("", value: $model.options.size, format: .number.precision(.fractionLength(0...2)))
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("cm").foregroundStyle(.secondary)
                    }
                }
            }

            Section("Output") {
                Picker("Save to", selection: $model.destination) {
                    Text("Next to original").tag(AppModel.Destination.besideOriginal)
                    Text("Folder").tag(AppModel.Destination.folder)
                }
                if model.destination == .folder {
                    HStack {
                        Text(model.folder?.lastPathComponent ?? "None chosen")
                            .foregroundStyle(model.folder == nil ? .secondary : .primary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Choose…") { if let f = Panels.chooseFolder() { model.folder = f } }
                    }
                }
                Toggle("Export when files are dropped", isOn: $model.exportOnDrop)
            }

            Section {
                Button("Reset to Defaults") { model.options = ConversionOptions() }
                    .buttonStyle(.link)
            }
        }
        .formStyle(.grouped)
    }

    enum IntersectionPreset: Hashable { case crisp, soft, round, custom }

    private var intersectionPreset: Binding<IntersectionPreset> {
        Binding(
            get: {
                switch model.options.fillet {
                case 0: .crisp
                case 0.3: .soft
                case 0.7: .round
                default: .custom
                }
            },
            set: { preset in
                switch preset {
                case .crisp: model.options.fillet = 0
                case .soft: model.options.fillet = 0.3
                case .round: model.options.fillet = 0.7
                case .custom: break
                }
            })
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: {
                let c = Converter.parseHex(model.options.color)
                return Color(red: c.x, green: c.y, blue: c.z)
            },
            set: { color in
                guard let c = NSColor(color).usingColorSpace(.sRGB) else { return }
                model.options.color = String(format: "#%02X%02X%02X",
                                             Int(round(c.redComponent * 255)),
                                             Int(round(c.greenComponent * 255)),
                                             Int(round(c.blueComponent * 255)))
            })
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String
    var help: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value)).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
                .labelsHidden()
        }
        .help(help)
    }
}
