using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IGenericSchoolService
    {
        // Classes
        Task<List<GenericClassModel>> GetClassesAsync(string farmId);
        Task<int> UpsertClassAsync(string farmId, GenericClassModel m);
        Task DeleteClassAsync(int id, string farmId);

        // Academic Terms
        Task<List<GenericAcademicTermModel>> GetTermsAsync(string farmId);
        Task<int> UpsertTermAsync(string farmId, GenericAcademicTermModel m);
        Task DeleteTermAsync(int id, string farmId);

        // Customer/Student Attendance (migration 367)
        Task<List<GenericCustomerAttendanceModel>> GetCustomerAttendanceAsync(string farmId, DateTime? date, int? classId);
        Task<int> UpsertCustomerAttendanceAsync(string farmId, GenericCustomerAttendanceModel m);
        Task DeleteCustomerAttendanceAsync(int id, string farmId);
    }
}
