import SwiftUI
import NetheriteCore

// Temporary placeholders, replaced as each phase lands.
struct SlidesView: View { let path: String; var body: some View { ContentUnavailableView("Slides", systemImage: "play.rectangle") } }
struct ImporterView: View { var body: some View { ContentUnavailableView("Importer", systemImage: "square.and.arrow.down") } }
struct PublishView: View { var body: some View { ContentUnavailableView("Publish", systemImage: "paperplane") } }
struct WorkspacesView: View { var body: some View { ContentUnavailableView("Workspaces", systemImage: "rectangle.3.offgrid") } }
struct FileRecoveryView: View { let path: String; var body: some View { ContentUnavailableView("File recovery", systemImage: "clock.arrow.circlepath") } }
struct AudioRecorderView: View { var body: some View { ContentUnavailableView("Audio recorder", systemImage: "mic") } }
struct CanvasEditor: View { let path: String; var body: some View { ContentUnavailableView("Canvas", systemImage: "rectangle.3.group") } }
struct BaseView: View { let path: String; var body: some View { ContentUnavailableView("Bases", systemImage: "tablecells") } }
struct GraphView: View { let focus: String?; var body: some View { ContentUnavailableView("Graph", systemImage: "point.3.connected.trianglepath.dotted") } }
struct WebViewer: View { let url: URL; var body: some View { ContentUnavailableView("Web viewer", systemImage: "globe") } }
extension View { func snapshotting(_ model: VaultModel) -> some View { self } }
