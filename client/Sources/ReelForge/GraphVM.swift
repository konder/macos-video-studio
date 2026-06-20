import Foundation
import CoreGraphics

// Graph IR(nodes:{id:{class_type,inputs,pos}})→ 可渲染模型。
// inputs 异构(标量=widget 参数;[srcId, slot]=连线),用 JSONSerialization 解析,不走 Codable。

struct NodeVM: Identifiable {
    let id: String
    let classType: String
    let pos: CGPoint
    let params: [(String, String)]      // 标量输入(widget 取值)
}

struct GraphLink: Identifiable {
    let id = UUID()
    let from: String                    // 源节点 id
    let to: String                      // 目标节点 id
    let toInput: String                 // 目标输入名
}

private func scalarString(_ v: Any) -> String? {
    if let s = v as? String { return s }
    if let n = v as? NSNumber { return n.stringValue }
    if let b = v as? Bool { return b ? "true" : "false" }
    return nil
}

private func num(_ v: Any?) -> Double {
    (v as? NSNumber)?.doubleValue ?? (v as? Double) ?? 0
}

func parseGraph(_ graph: [String: Any]) -> ([NodeVM], [GraphLink]) {
    let nodes = (graph["nodes"] as? [String: Any]) ?? graph
    var vms: [NodeVM] = []
    var links: [GraphLink] = []
    for (id, raw) in nodes {
        guard let nd = raw as? [String: Any] else { continue }
        let ct = nd["class_type"] as? String ?? "?"
        let posArr = nd["pos"] as? [Any] ?? []
        let pos = CGPoint(x: num(posArr.first), y: num(posArr.count > 1 ? posArr[1] : nil))
        var params: [(String, String)] = []
        let inputs = nd["inputs"] as? [String: Any] ?? [:]
        for (k, v) in inputs {
            if let arr = v as? [Any], let first = arr.first, !(first is NSNumber && arr.count == 1) {
                // 连线:[srcId, slot]
                let src = (first as? String) ?? scalarString(first) ?? ""
                if !src.isEmpty { links.append(GraphLink(from: src, to: id, toInput: k)) }
            } else if let s = scalarString(v) {
                params.append((k, s))
            }
        }
        params.sort { $0.0 < $1.0 }
        vms.append(NodeVM(id: id, classType: ct, pos: pos, params: params))
    }
    vms.sort { ($0.pos.x, $0.pos.y) < ($1.pos.x, $1.pos.y) }
    return (vms, links)
}
