/** Checks for the custom-connector answers the connector panel reads (the list itself is parsed in lib/answers/profile.ts). */
import { anything, arrayOf, isBoolean, isString, objectOf, objectWithOptional, parseAnswer } from '../../lib/check.ts'
import type { Connector } from '../../lib/types.ts'

/** An action a bot prepared on a custom connector; the owner reviews it before it runs. */
export interface ConnectorApproval {
  id: string
  state: string
  tool: string
  argsJSON: string
  actionHash: string
  connectorId: string
  expiresAt: string
}

export interface ConnectorTool {
  name: string
  description?: string
}

interface ApprovalList {
  approvals: ConnectorApproval[]
}

interface ConnectorAnswer {
  connector: Connector
}

interface ApprovalAnswer {
  approval: ConnectorApproval
}

interface ToolList {
  tools?: ConnectorTool[]
}

interface ExecuteAnswer {
  result?: unknown
}

const isConnector = objectWithOptional<Connector>({ id: isString, name: isString }, { revoked: isBoolean })
const isApproval = objectOf<ConnectorApproval>({
  id: isString, state: isString, tool: isString, argsJSON: isString, actionHash: isString, connectorId: isString, expiresAt: isString,
})
const isTool = objectWithOptional<ConnectorTool>({ name: isString }, { description: isString })
const isApprovalList = objectOf<ApprovalList>({ approvals: arrayOf(isApproval) })
const isConnectorAnswer = objectOf<ConnectorAnswer>({ connector: isConnector })
const isApprovalAnswer = objectOf<ApprovalAnswer>({ approval: isApproval })
const isToolList = objectWithOptional<ToolList>({}, { tools: arrayOf(isTool) })
const isExecuteAnswer = objectWithOptional<ExecuteAnswer>({}, { result: anything })

export const parseApprovalList = (answer: unknown): ConnectorApproval[] => parseAnswer(isApprovalList, answer, 'approval list').approvals
export const parseConnectorAnswer = (answer: unknown): Connector => parseAnswer(isConnectorAnswer, answer, 'connector').connector
export const parseApprovalAnswer = (answer: unknown): ConnectorApproval => parseAnswer(isApprovalAnswer, answer, 'approval').approval
export const parseTools = (answer: unknown): ConnectorTool[] => parseAnswer(isToolList, answer, 'tool list').tools ?? []
export const parseExecuteResult = (answer: unknown): unknown => parseAnswer(isExecuteAnswer, answer, 'result').result
