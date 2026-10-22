import SwiftUI
import TubelineCore

struct SettingsPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Settings Scope", selection: $model.editingScope) {
                    Text("Batch").tag(AppModel.EditingScope.batch)
                    Text("Selected Icon").tag(AppModel.EditingScope.selected).disabled(model.selectedJob == nil)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if model.editingScope == .selected {
                    Text(model.selectedJob?.hasOverrides == true ? "This icon has custom settings. Other values follow the batch." : "Uses batch settings. Changes here customize only this icon.")
                        .font(.caption).foregroundStyle(.secondary)
                    if model.selectedJob?.hasOverrides == true {
                        Button("Use Batch Settings") { model.resetSelectedOverrides() }
                            .controlSize(.small)
                    }
                } else {
                    Text("Applies to every icon, except values customized individually.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(16)
            Divider()
            Form {
                Section("Shape") {
                    LabeledSlider(title: "Thickness", value: $model.editingOptions.thickness, range: 0.25...3, step: 0.05,
                                  format: { String(format: "%.2f×", $0) }, help: "Tube diameter as a multiple of the SVG stroke width.")
                    Picker("Intersections", selection: intersectionPreset) {
                        Text("Crisp").tag(IntersectionPreset.crisp)
                        Text("Soft").tag(IntersectionPreset.soft)
                        Text("Round").tag(IntersectionPreset.round)
                        if intersectionPreset.wrappedValue == .custom { Text("Custom").tag(IntersectionPreset.custom) }
                    }
                    .help("Controls the blend where separate strokes meet.")
                    Picker("Ends", selection: $model.editingOptions.caps) {
                        Text("From SVG").tag(ConversionOptions.Caps.svg)
                        Text("Round").tag(ConversionOptions.Caps.round)
                        Text("Flat").tag(ConversionOptions.Caps.flat)
                    }
                }
                Section("Surface") {
                    Picker("Material", selection: $model.editingOptions.surface) {
                        Text("Solid Color").tag(ConversionOptions.Surface.solid)
                        Text("Shaded").tag(ConversionOptions.Surface.shaded)
                    }
                    .help("Solid Color ignores lighting. Shaded responds to lights in your motion graphics app.")
                    ColorPicker("Color", selection: colorBinding, supportsOpacity: false)
                }
                Section("Size") {
                    Picker("Scale", selection: $model.editingOptions.sizing) {
                        Text("Artwork Points").tag(ConversionOptions.Sizing.points)
                        Text("SVG Physical Size").tag(ConversionOptions.Sizing.physical)
                        Text("Fit Size").tag(ConversionOptions.Sizing.fixed)
                    }
                    if model.editingOptions.sizing == .fixed {
                        HStack {
                            Text("Longest Side")
                            Spacer()
                            TextField("Longest Side in Centimeters", value: $model.editingOptions.size, format: .number.precision(.fractionLength(0...2)))
                                .labelsHidden().multilineTextAlignment(.trailing).frame(width: 70)
                            Text("cm").foregroundStyle(.secondary)
                        }
                    }
                    Picker("Frame", selection: $model.editingOptions.framing) {
                        Text("SVG Canvas").tag(ConversionOptions.Framing.canvas)
                        Text("Artwork").tag(ConversionOptions.Framing.content)
                    }
                    .help("Uses the canvas or artwork bounds to center the model. Fit Size scales this frame.")
                    HStack {
                        Text("Output Scale")
                        Spacer()
                        TextField("Output Scale Multiplier", value: $model.editingOptions.outputScale, format: .number)
                            .labelsHidden().multilineTextAlignment(.trailing).frame(width: 55)
                        Text("×").foregroundStyle(.secondary)
                        Stepper("Output Scale", value: $model.editingOptions.outputScale, in: 1...10_000)
                            .labelsHidden().fixedSize()
                    }
                    .help("Multiplies the model's final dimensions. Use a larger scale for 3D apps that work with larger objects.")
                    HStack(spacing: 8) {
                        Text("Presets").font(.caption).foregroundStyle(.secondary)
                        ForEach([1, 10, 100], id: \.self) { scale in
                            Button("\(scale)×") { model.editingOptions.outputScale = scale }
                                .accessibilityLabel("Set Output Scale to \(scale) Times")
                        }
                    }
                    .controlSize(.small)
                    Text(sizeExplanation).font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    DisclosureGroup("Advanced") {
                        LabeledSlider(title: "Detail", value: $model.editingOptions.facets, range: 12...96, step: 2,
                                      format: { "\(Int($0))" }, help: "Target curve detail. Higher values produce smoother silhouettes and heavier meshes.")
                        Toggle("Optimize Mesh", isOn: $model.editingOptions.optimize)
                        LabeledSlider(title: "Intersection Blend", value: $model.editingOptions.fillet, range: 0...1, step: 0.05,
                                      format: { $0 == 0 ? "None" : String(format: "%.2f", $0) })
                        Toggle("Include Fills", isOn: $model.editingOptions.includeFills)
                        if model.editingOptions.includeFills {
                            Picker("Fills Without Outlines", selection: $model.editingOptions.fillStyle) {
                                Text("Extrude").tag(ConversionOptions.FillStyle.extruded)
                                Text("Rounded").tag(ConversionOptions.FillStyle.rounded)
                            }
                            if model.editingOptions.fillStyle == .extruded {
                                HStack {
                                    Text("Depth")
                                    Spacer()
                                    TextField("Extrusion Depth in Points", value: $model.editingOptions.extrudeDepth, format: .number.precision(.fractionLength(0...2)))
                                        .labelsHidden().multilineTextAlignment(.trailing).frame(width: 65)
                                    Text("pt").foregroundStyle(.secondary)
                                }
                                LabeledSlider(title: "Edge Rounding", value: $model.editingOptions.extrudeRounding, range: 0...1, step: 0.05,
                                              format: { $0 == 0 ? "Sharp" : String(format: "%.2f", $0) })
                            }
                        }
                        if model.editingOptions.sizing == .points {
                            HStack {
                                Text("Millimeters per Point")
                                Spacer()
                                TextField("Millimeters per Artwork Point", value: $model.editingOptions.millimetersPerPoint, format: .number.precision(.fractionLength(0...4)))
                                    .labelsHidden().multilineTextAlignment(.trailing).frame(width: 75)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 0, maxHeight: .infinity)
            .disabled(model.editingScope == .selected && model.selectedJob == nil)
            if model.editingScope == .batch {
                Divider()
                HStack {
                    Button("Restore Saved Defaults") { model.restoreDefaults() }
                    Spacer()
                }
                .controlSize(.small).padding(12)
            }
        }
    }

    private var sizeExplanation: String {
        switch model.editingOptions.sizing {
        case .points: "Uses artwork points at 1/72 inch by default. Motion’s Automatic size fits imported objects to its canvas."
        case .physical: "Uses the SVG’s declared dimensions. CSS pixels and print points have different physical sizes."
        case .fixed: "Sets the frame’s longest side. Motion’s Automatic size may normalize the imported model."
        }
    }

    private var intersectionPreset: Binding<IntersectionPreset> {
        Binding(get: {
            switch model.editingOptions.fillet {
            case 0: .crisp
            case 0.3: .soft
            case 0.7: .round
            default: .custom
            }
        }, set: { preset in
            switch preset {
            case .crisp: model.editingOptions.fillet = 0
            case .soft: model.editingOptions.fillet = 0.3
            case .round: model.editingOptions.fillet = 0.7
            case .custom: break
            }
        })
    }

    private var colorBinding: Binding<Color> {
        Binding(get: {
            let c = Converter.parseHex(model.editingOptions.color)
            return Color(red: c.x, green: c.y, blue: c.z)
        }, set: { color in
            guard let c = NSColor(color).usingColorSpace(.sRGB) else { return }
            model.editingOptions.color = String(format: "#%02X%02X%02X", Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
        })
    }
}
