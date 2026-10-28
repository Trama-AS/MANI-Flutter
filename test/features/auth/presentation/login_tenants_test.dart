import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mani/features/auth/presentation/pages/login_page.dart';

void main() {
  group('resolverTenantsLogin (SCRUM-1361)', () {
    test('devuelve tenants de QA si el slug es acme-servicios', () {
      final tenants = resolverTenantsLogin(slug: 'acme-servicios');
      expect(tenants, ['ACME Servicios', 'Nova Mantenimiento']);
    });

    test('devuelve tenants de QA si la url contiene hpsxdotaizzclkeufzct', () {
      final tenants = resolverTenantsLogin(
        supabaseUrl: 'https://hpsxdotaizzclkeufzct.supabase.co',
      );
      expect(tenants, ['ACME Servicios', 'Nova Mantenimiento']);
    });

    test('devuelve tenants de producción si no es QA', () {
      final tenants = resolverTenantsLogin(slug: 'plomeria-express');
      expect(tenants, [
        'Plomería Express CDMX SA',
        'Electricistas Pro Monterrey',
        'Cerrajería Total GDL',
      ]);
    });

    test('consulta dotenv cuando no se le pasan parámetros en QA', () {
      dotenv.testLoad(
        fileInput:
            'TENANT_SLUG=acme-servicios\nSUPABASE_URL=https://hpsxdotaizzclkeufzct.supabase.co',
      );
      final tenants = resolverTenantsLogin();
      expect(tenants, ['ACME Servicios', 'Nova Mantenimiento']);
    });

    test('consulta dotenv cuando no se le pasan parámetros en prod', () {
      dotenv.testLoad(
        fileInput:
            'TENANT_SLUG=plomeria-express\nSUPABASE_URL=https://tjxueukivwxsgipltqwb.supabase.co',
      );
      final tenants = resolverTenantsLogin();
      expect(tenants, contains('Plomería Express CDMX SA'));
    });
  });
}
