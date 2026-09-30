import SwiftUI
import NetheriteCore

// Temporary placeholders, replaced as each phase lands.
struct ImporterView: View { var body: some View { ContentUnavailableView("Importer", systemImage: "square.and.arrow.down") } }
struct PublishView: View { var body: some View { ContentUnavailableView("Publish", systemImage: "paperplane") } }
struct CanvasEditor: View { let path: String; var body: some View { ContentUnavailableView("Canvas", systemImage: "rectangle.3.group") } }
struct BaseView: View { let path: String; var body: some View { ContentUnavailableView("Bases", systemImage: "tablecells") } }
struct GraphView: View { let focus: String?; var body: some View { ContentUnavailableView("Graph", systemImage: "point.3.connected.trianglepath.dotted") } }
