import SwiftUI

/// The video footer keeps AI declarations; expanded details can also show publication metadata.
struct DYWorkMetadataText: View {
    let item: DYAweme
    let active: Bool
    var showsPublication = true
    @State private var recovered: (id: String, city: String?, country: String?)?
    private struct Key: Hashable {
        let id: String; let active: Bool
        let city: String?; let country: String?
    }
    var body: some View {
        let stored = recovered?.id == item.id ? recovered : nil
        // Prepared neighbours and disk-cache hits are available on the first render, not a later task hop.
        let cached = DYPublicationRegionClient.shared.cached(item.id)
        let place = DYPublicationRegion.name(for: item.publicationCityCode, country: item.publicationCountry)
            ?? DYPublicationRegion.name(for: stored?.city, country: stored?.country)
            ?? DYPublicationRegion.name(for: cached?.city, country: cached?.country)
        // Missing web metadata is not a confirmed unknown: show the region once resolved.
        Group {
            if showsPublication,
               let text = DYPublicationRegion.metadata(item.metadataText(), place: place, resolved: stored != nil || cached != nil) {
                Text(text).accessibilityIdentifier("douyin.video.metadata")
            } else if !showsPublication,
                      let declaration = item.aiDeclaration?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !declaration.isEmpty {
                Text(declaration).accessibilityIdentifier("douyin.video.metadata")
            }
        }
        .task(id: Key(id: item.id, active: active,
                      city: item.publicationCityCode, country: item.publicationCountry)) {
            // Lazy-mounted neighbouring pages prepare their metadata before becoming current.
            guard showsPublication, place == nil else { return }
            let result = await DYPublicationRegionClient.shared.lookup(item.id)
            guard !Task.isCancelled else { return }
            recovered = (item.id, result.city, result.country)
        }
    }
}
