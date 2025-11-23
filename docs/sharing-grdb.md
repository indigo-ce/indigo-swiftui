# SQLiteData Guide

## Introduction

SQLiteData is a fast, lightweight replacement for SwiftData that deploys back to iOS 13. It combines the power of SQLite with type-safe query building and automatic SwiftUI observation.

```swift
// SwiftData
@Query var items: [Item]

// SharingGRDB
@FetchAll var items: [Item]
```

Key advantages:

- **Broader platform support**: iOS 13+ vs SwiftData's iOS 17+
- **Direct SQLite access**: Full control over schema and migrations
- **Works everywhere**: SwiftUI views, @Observable models, UIKit controllers
- **Type-safe queries**: Compile-time protection against typos and type errors

## Setup

```swift
@main
struct MyApp: App {
  init() {
    prepareDependencies {
      $0.defaultDatabase = try! appDatabase()
    }
  }
}

func appDatabase() throws -> any DatabaseWriter {
  let db = try DatabaseQueue(path: "app.sqlite")
  var migrator = DatabaseMigrator()

  migrator.registerMigration("Create items") { db in
    try #sql(
      """
      CREATE TABLE items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        isCompleted INTEGER NOT NULL DEFAULT 0
      )
      """
    ).execute(db)
  }

  try migrator.migrate(db)
  return db
}
```

## Basic Usage

### Define Your Schema

```swift
@Table
struct Item: Identifiable {
  let id: Int
  var title = ""
  var isCompleted = false
  var priority: Priority?
}

enum Priority: Int, QueryBindable {
  case low, medium, high
}
```

### Fetch Data

```swift
struct ItemsView: View {
  @FetchAll var items: [Item]
  @FetchAll(Item.where(\.isCompleted).order(by: \.title))
  var completedItems: [Item]

  @FetchOne(Item.count())
  var totalCount = 0

  var body: some View {
    List(items) { item in
      Text(item.title)
    }
  }
}
```

### Observable Models

```swift
@Observable
class ItemsModel {
  @ObservationIgnored
  @FetchAll var items: [Item]

  @ObservationIgnored
  @Dependency(\.defaultDatabase) var database

  func addItem(_ title: String) async throws {
    try await database.write { db in
      try Item.insert {
        Item.Draft(title: title)
      }.execute(db)
    }
  }
}
```

## Intermediate Queries

### Filtering and Sorting

```swift
// Multiple conditions
@FetchAll(
  Item
    .where { !$0.isCompleted && $0.priority.eq(.high) }
    .order { ($0.priority.desc(), $0.title) }
    .limit(10)
)
var urgentItems: [Item]

// Dynamic queries
@FetchAll var searchResults: [Item]

func search(_ text: String) async {
  await $searchResults.load(
    Item.where { $0.title.contains(text) }
  )
}
```

### Custom Selections

```swift
@Selection
struct ItemSummary {
  let title: String
  let priority: Priority?
}

@FetchAll(
  Item
    .where { !$0.isCompleted }
    .select {
      ItemSummary.Columns(
        title: $0.title,
        priority: $0.priority
      )
    }
)
var summaries: [ItemSummary]
```

### Aggregations

```swift
@Selection
struct PriorityCount {
  let priority: Priority?
  let count: Int
}

@FetchAll(
  Item
    .group(by: \.priority)
    .select {
      PriorityCount.Columns(
        priority: $0.priority,
        count: $0.count()
      )
    }
)
var priorityCounts: [PriorityCount]
```

## Advanced Queries

### Joins and Associations

```swift
@Table
struct Category: Identifiable {
  let id: Int
  var name = ""
}

@Table
struct Item: Identifiable {
  let id: Int
  var title = ""
  var categoryID: Category.ID
}

@Selection
struct ItemWithCategory {
  let item: Item
  let categoryName: String
}

@FetchAll(
  Item
    .join(Category.all) { $0.categoryID.eq($1.id) }
    .select {
      ItemWithCategory.Columns(
        item: $0,
        categoryName: $1.name
      )
    }
)
var itemsWithCategories: [ItemWithCategory]
```

### JSON Aggregations (Pre-loading Associations)

```swift
@Selection
struct CategoryWithItems {
  let category: Category
  @Column(as: [Item].JSONRepresentation.self)
  let items: [Item]
}

@FetchAll(
  Category
    .leftJoin(Item.all) { $0.id.eq($1.categoryID) }
    .select {
      CategoryWithItems.Columns(
        category: $0,
        items: $1.jsonGroupArray()
      )
    }
)
var categoriesWithItems: [CategoryWithItems]
```

### Multiple Queries in One Transaction

```swift
struct DashboardData: FetchKeyRequest {
  struct Value {
    var totalItems = 0
    var completedItems: [Item] = []
    var urgentItems: [Item] = []
  }

  func fetch(_ db: Database) throws -> Value {
    try Value(
      totalItems: Item.fetchCount(db),
      completedItems: Item.where(\.isCompleted).fetchAll(db),
      urgentItems: Item.where { $0.priority.eq(.high) }.fetchAll(db)
    )
  }
}

@Fetch(DashboardData())
var dashboard = DashboardData.Value()
```

## TCA Integration

### State and Actions

```swift
@Reducer
struct ItemsFeature {
  @ObservableState
  struct State {
    @ObservationStateIgnored
    @FetchAll var items: [Item] = []
    var isLoading = false
  }

  enum Action {
    case onAppear
    case addItem(String)
    case itemsUpdated([Item])
  }
}
```

### Effects and Publishers

```swift
var body: some ReducerOf<Self> {
  Reduce { state, action in
    switch action {
    case .onAppear:
      return .publisher {
        state.$items.publisher.map(Action.itemsUpdated)
      }

    case .addItem(let title):
      return .run { _ in
        try await database.write { db in
          try Item.insert {
            Item.Draft(title: title)
          }.execute(db)
        }
      }

    case .itemsUpdated(let items):
      state.items = items
      return .none
    }
  }
}
```

### Key Points for TCA

- Use `@ObservationStateIgnored` with `@FetchAll` in state
- Don't mutate the fetched property in reducers - it updates automatically
- Use `.publisher { state.$property.publisher.map(Action.updated) }` for observation
- Database writes trigger automatic updates to all relevant `@FetchAll` properties
