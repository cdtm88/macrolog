import SwiftUI
import SwiftData

/// Configure the favourites that appear as one-tap chips under the text entry
/// box. Add, edit, reorder, delete — capped at `Favorite.maxCount`.
struct FavoritesView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Favorite.sortOrder) private var favorites: [Favorite]

    @State private var editingFavorite: Favorite?
    @State private var isAddingNew = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(favorites) { favorite in
                        Button { editingFavorite = favorite } label: {
                            row(favorite)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: delete)
                    .onMove(perform: move)

                    if favorites.count < Favorite.maxCount {
                        Button { isAddingNew = true } label: {
                            Label("Add favourite", systemImage: "plus.circle.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                } footer: {
                    Text("Meals you log regularly, with known values. They appear under the text box for one-tap logging — no AI estimate needed. Up to \(Favorite.maxCount).")
                }
            }
            .navigationTitle("Favourites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                if !favorites.isEmpty {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                }
            }
            .sheet(item: $editingFavorite) { favorite in
                FavoriteEditor(favorite: favorite)
            }
            .sheet(isPresented: $isAddingNew) {
                FavoriteEditor(favorite: nil, nextSortOrder: (favorites.map(\.sortOrder).max() ?? -1) + 1)
            }
        }
    }

    private func row(_ favorite: Favorite) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(favorite.name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
            HStack(spacing: 12) {
                Text("\(Int(favorite.kcal.rounded())) kcal").foregroundStyle(Theme.secondary)
                Text("\(Int(favorite.protein.rounded()))P").foregroundStyle(Theme.protein)
                Text("\(Int(favorite.carbs.rounded()))C").foregroundStyle(Theme.carbs)
                Text("\(Int(favorite.fat.rounded()))F").foregroundStyle(Theme.fat)
            }
            .font(.system(size: 12, weight: .medium))
        }
        .padding(.vertical, 2)
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets { context.delete(favorites[index]) }
        try? context.save()
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = favorites
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, favorite) in reordered.enumerated() {
            favorite.sortOrder = index
        }
        try? context.save()
    }
}

/// Add or edit one favourite: name plus the four known macro values.
private struct FavoriteEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let favorite: Favorite?          // nil = creating a new one
    var nextSortOrder: Int = 0

    @State private var name: String
    @State private var kcal: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?

    init(favorite: Favorite?, nextSortOrder: Int = 0) {
        self.favorite = favorite
        self.nextSortOrder = nextSortOrder
        _name = State(initialValue: favorite?.name ?? "")
        _kcal = State(initialValue: favorite?.kcal)
        _protein = State(initialValue: favorite?.protein)
        _carbs = State(initialValue: favorite?.carbs)
        _fat = State(initialValue: favorite?.fat)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && kcal != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal") {
                    TextField("e.g. Usual breakfast", text: $name)
                }
                Section("Macros") {
                    numberRow("Calories", unit: "kcal", value: $kcal)
                    numberRow("Protein", unit: "g", value: $protein)
                    numberRow("Carbs", unit: "g", value: $carbs)
                    numberRow("Fat", unit: "g", value: $fat)
                }
            }
            .navigationTitle(favorite == nil ? "New favourite" : "Edit favourite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
        }
    }

    private func numberRow(_ label: String, unit: String, value: Binding<Double?>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(unit)
                .foregroundStyle(Theme.secondary)
                .frame(width: 36, alignment: .leading)
        }
    }

    private func save() {
        let macros = Macros(kcal: kcal ?? 0,
                            protein: protein ?? 0,
                            carbs: carbs ?? 0,
                            fat: fat ?? 0)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let favorite {
            favorite.name = trimmed
            favorite.macros = macros
        } else {
            context.insert(Favorite(name: trimmed, macros: macros, sortOrder: nextSortOrder))
        }
        try? context.save()
        dismiss()
    }
}
