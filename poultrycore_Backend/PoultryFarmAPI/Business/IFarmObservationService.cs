using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IFarmObservationService
    {
        /// <summary>Get or create the notes row for the given farm + week.</summary>
        Task<FarmObservationModel?> GetByWeek(string farmId, DateTime weekStartDate);
        Task<List<FarmObservationModel>> GetAll(string farmId);
        /// <summary>Insert if absent, update if present (composite unique on FarmId+WeekStartDate).</summary>
        Task<FarmObservationModel?> Upsert(FarmObservationModel model);
    }
}
