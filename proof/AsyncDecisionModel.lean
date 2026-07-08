/-
Minimal executable/checked model for the ratmac async decision writer.

Intent modelled:
* accepting a decision only enqueues writer work and never waits;
* accepted decisions are tracked until the async writer records or fails them;
* an ack is a separate step that is enabled only after terminal persistence;
* external IPC wait is represented by status `blocked` and only a response unblocks it.
-/

namespace Ratmac.AsyncDecision

abbrev Id := Nat

inductive PersistState where
  | fresh
  | accepted
  | recorded
  | failed
  deriving DecidableEq, Repr

inductive PersistResult where
  | ok
  | err
  deriving DecidableEq, Repr

inductive IpcState where
  | idle
  | blocked
  | responded
  deriving DecidableEq, Repr

inductive StepKind where
  | noWait
  | asyncWait
  deriving DecidableEq, Repr

inductive Event where
  | accept (id : Id)
  | writerDone (id : Id) (result : PersistResult)
  | ack (id : Id)
  | sendIpc (id : Id)
  | recvIpc (id : Id)
  deriving DecidableEq, Repr

structure Model where
  persist : Id -> PersistState
  acked : Id -> Bool
  ipc : Id -> IpcState

namespace Model

def initial : Model where
  persist := fun _ => PersistState.fresh
  acked := fun _ => false
  ipc := fun _ => IpcState.idle

def withPersist (s : Model) (id : Id) (p : PersistState) : Model :=
  { s with persist := fun j => if j = id then p else s.persist j }

def withAck (s : Model) (id : Id) : Model :=
  { s with acked := fun j => if j = id then true else s.acked j }

def withIpc (s : Model) (id : Id) (p : IpcState) : Model :=
  { s with ipc := fun j => if j = id then p else s.ipc j }

end Model

open PersistState PersistResult IpcState StepKind Event

/-- A decision is still known to the model. `fresh` means no accepted decision exists. -/
def tracked : PersistState -> Prop
  | fresh => False
  | accepted => True
  | recorded => True
  | failed => True

/-- Terminal persistence states. -/
def terminal : PersistState -> Prop
  | recorded => True
  | failed => True
  | fresh => False
  | accepted => False

def resultState : PersistResult -> PersistState
  | ok => recorded
  | err => failed

/-- Which events may wait on an external condition. Accept and ack steps are local/no-wait. -/
def kind : Event -> StepKind
  | accept _ => noWait
  | writerDone _ _ => noWait
  | ack _ => noWait
  | sendIpc _ => noWait
  | recvIpc _ => noWait

/-- Acknowledgement discipline: a decision can be acknowledged only after persistence is terminal. -/
def ackEnabled (s : Model) (id : Id) : Prop :=
  terminal (s.persist id)

/-- Single-step transition. No transition removes a tracked accepted decision. -/
def step (e : Event) (s : Model) : Model :=
  match e with
  | accept id => s.withPersist id accepted
  | writerDone id result =>
      match s.persist id with
      | accepted => s.withPersist id (resultState result)
      | _ => s
  | ack id =>
      match s.persist id with
      | recorded => s.withAck id
      | failed => s.withAck id
      | _ => s
  | sendIpc id => s.withIpc id blocked
  | recvIpc id => s.withIpc id responded

/-- Execute a finite trace. -/
def run : List Event -> Model -> Model
  | [], s => s
  | e :: es, s => run es (step e s)

/-- Accept/enqueue is explicitly classified as no-wait and immediately tracks the decision. -/
theorem accept_nonblocking (s : Model) (id : Id) :
    kind (accept id) = noWait ∧ (step (accept id) s).persist id = accepted := by
  constructor
  · rfl
  · simp [step, Model.withPersist]

/-- Accepting one decision does not synchronously change any other decision. -/
theorem accept_only_touches_id (s : Model) {id other : Id} (h : other ≠ id) :
    (step (accept id) s).persist other = s.persist other := by
  simp [step, Model.withPersist, h]

/-- Once the async writer completes an accepted decision, persistence is terminal. -/
theorem writer_done_terminal (s : Model) (id : Id) (result : PersistResult)
    (h : s.persist id = accepted) :
    terminal ((step (writerDone id result) s).persist id) := by
  cases result <;> simp [step, h, Model.withPersist, resultState, terminal]

/-- More precise form of the writer completion theorem. -/
theorem writer_done_records_or_fails (s : Model) (id : Id) (result : PersistResult)
    (h : s.persist id = accepted) :
    (step (writerDone id result) s).persist id = recorded ∨
      (step (writerDone id result) s).persist id = failed := by
  cases result <;> simp [step, h, Model.withPersist, resultState]

/-- Ack is enabled exactly by the terminal persistence predicate. -/
theorem ack_enabled_iff_terminal (s : Model) (id : Id) :
    ackEnabled s id ↔ terminal (s.persist id) := by
  rfl

/-- If ack discipline enables an ack, the ack step records the ack bit. -/
theorem enabled_ack_sets_ack (s : Model) (id : Id) (h : ackEnabled s id) :
    (step (ack id) s).acked id = true := by
  cases hp : s.persist id <;> simp [ackEnabled, terminal, hp, step, Model.withAck] at h ⊢

/-- One step never loses a decision that was already tracked. -/
theorem tracked_after_step (s : Model) (e : Event) (id : Id)
    (h : tracked (s.persist id)) :
    tracked ((step e s).persist id) := by
  cases e with
  | accept j =>
      by_cases hj : id = j
      · subst id
        simp [step, Model.withPersist, tracked]
      · simp [step, Model.withPersist, hj, h]
  | writerDone j result =>
      by_cases hj : id = j
      · subst id
        cases hs : s.persist j <;> cases result <;> simp [step, hs, Model.withPersist, resultState, tracked] at h ⊢
      · cases hs : s.persist j <;> simp [step, hs, Model.withPersist, hj, h]
  | ack j =>
      cases hs : s.persist j <;> simp [step, hs, Model.withAck, h]
  | sendIpc j =>
      simp [step, Model.withIpc, h]
  | recvIpc j =>
      simp [step, Model.withIpc, h]

/-- A finite trace cannot lose a decision that was already accepted/tracked. -/
theorem tracked_after_run (events : List Event) (s : Model) (id : Id)
    (h : tracked (s.persist id)) :
    tracked ((run events s).persist id) := by
  induction events generalizing s with
  | nil => simpa [run] using h
  | cons e es ih =>
      exact ih (step e s) (tracked_after_step s e id h)

/-- Accepted decisions are never lost through later acks, IPC steps, or writer completions. -/
theorem accepted_not_lost_after_run (events : List Event) (s : Model) (id : Id)
    (h : s.persist id = accepted) :
    tracked ((run events s).persist id) := by
  exact tracked_after_run events s id (by simp [tracked, h])

/-- Sending external IPC moves the request to blocked without waiting for a response. -/
theorem send_ipc_blocks_nonblocking (s : Model) (id : Id) :
    kind (sendIpc id) = noWait ∧ (step (sendIpc id) s).ipc id = blocked := by
  constructor
  · rfl
  · simp [step, Model.withIpc]

/-- While IPC is blocked, only the matching response event can unblock it. -/
theorem ipc_blocked_until_response (s : Model) (id : Id) (e : Event)
    (hblocked : s.ipc id = blocked)
    (hnotresp : e ≠ recvIpc id) :
    (step e s).ipc id = blocked := by
  cases e with
  | accept j => simp [step, hblocked, Model.withPersist]
  | writerDone j result =>
      cases hs : s.persist j <;> simp [step, hs, hblocked, Model.withPersist]
  | ack j =>
      cases hs : s.persist j <;> simp [step, hs, hblocked, Model.withAck]
  | sendIpc j =>
      by_cases hj : id = j
      · subst hj
        simp [step, Model.withIpc]
      · simp [step, Model.withIpc, hj, hblocked]
  | recvIpc j =>
      by_cases hj : j = id
      · subst hj
        contradiction
      · have hidj : id ≠ j := by
          intro h
          exact hj h.symm
        simp [step, Model.withIpc, hidj, hblocked]

/-- The matching response is the only modelled unblock transition. -/
theorem ipc_response_unblocks (s : Model) (id : Id) :
    (step (recvIpc id) s).ipc id = responded := by
  simp [step, Model.withIpc]

end Ratmac.AsyncDecision
