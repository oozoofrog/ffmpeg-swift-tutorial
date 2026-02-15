import Foundation

public enum DocumentPathResolver {
    public static func userDocumentRoot(from absoluteDocumentPath: String) -> String? {
        let components = absoluteDocumentPath.split(separator: "/").map(String.init)
        guard components.count >= 3 else { return nil }
        return "/" + components[0...2].joined(separator: "/") + "/Documents"
    }

    public static func appScopedDocumentAliasRoot(from absoluteDocumentPath: String, appName: String = "ffmpeg_tutorial") -> String? {
        guard let root = userDocumentRoot(from: absoluteDocumentPath) else { return nil }
        return root + "/" + appName
    }

    public static func needsSymlinkRefresh(currentLinkTarget: String?, expectedTarget: String) -> Bool {
        return currentLinkTarget != expectedTarget
    }
}
