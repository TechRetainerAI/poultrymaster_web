using PoultryFarmAPIWeb.Models;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace PoultryFarmAPIWeb.Business
{
    public interface IBirdFlockService
    {
        Task<int> CreateFlock(FlockModel model);
        Task UpdateFlock(FlockModel model);
        FlockModel GetFlockById(int flockId, string userId, string farmId);
        List<FlockModel> GetAllFlocks(string userId, string farmId);
        Task DeleteFlock(int flockId, string userId, string farmId);
        Task<int> GetBirdsConsumedFromBatch(int batchId, string userId, string farmId, int? flockIdToExclude = null);

        /// <summary>
        /// Divide a batch into many flocks in one transaction: all of them or none.
        /// Every row goes through the same <c>spflock_insert</c> as
        /// <see cref="CreateFlock"/>, so an allocated flock is indistinguishable
        /// from one added through the single Add Flock form.
        ///
        /// <para>
        /// Re-checks the batch total INSIDE the transaction, under a per-batch
        /// advisory lock, so two people allocating the same batch at the same
        /// moment cannot between them exceed it. Throws
        /// <see cref="FlockAllocationConflictException"/> when the birds are gone
        /// by the time the lock is held.
        /// </para>
        /// </summary>
        /// <returns>The created flocks, re-read from the database after commit.</returns>
        Task<List<FlockModel>> AllocateBatchToFlocks(
            string userId, string farmId, int batchId, int batchBirds, IReadOnlyList<FlockModel> flocks);
    }

    /// <summary>
    /// The batch ran out of birds between the user opening the tool and posting.
    /// Carries the numbers so the message can say what actually happened rather
    /// than "conflict".
    /// </summary>
    public class FlockAllocationConflictException : Exception
    {
        public int BatchBirds { get; }
        public int AlreadyAllocated { get; }
        public int Requested { get; }
        public int Available => Math.Max(0, BatchBirds - AlreadyAllocated);

        public FlockAllocationConflictException(int batchBirds, int alreadyAllocated, int requested)
            : base($"This allocation places {requested:N0} birds but the batch only has {Math.Max(0, batchBirds - alreadyAllocated):N0} left — someone else allocated from it while this was open.")
        {
            BatchBirds = batchBirds;
            AlreadyAllocated = alreadyAllocated;
            Requested = requested;
        }
    }
}
